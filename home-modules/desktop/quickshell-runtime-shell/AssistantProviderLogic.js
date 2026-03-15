.pragma library

var Providers = {
    OPENAI_COMPATIBLE: "openai_compatible",
    GOOGLE: "google"
};

function defaultConfig() {
    return {
        ai: {
            provider: Providers.OPENAI_COMPATIBLE,
            models: {
                openai_compatible: "gpt-4o-mini",
                google: "gemini-2.5-flash"
            },
            apiKeys: {},
            temperature: 0.7,
            systemPrompt: "You are a concise desktop assistant inside a QuickShell runtime panel. Prefer actionable answers and keep context in mind.",
            openaiLocal: false,
            openaiBaseUrl: "https://api.openai.com/v1/chat/completions"
        },
        translator: {
            backend: "google",
            sourceLanguage: "auto",
            targetLanguage: "en",
            realTimeTranslation: true,
            deeplApiKey: ""
        },
        ui: {
            scale: 1
        }
    };
}

function cloneValue(value) {
    return JSON.parse(JSON.stringify(value));
}

function normalizeConfig(config) {
    var defaults = defaultConfig();
    var next = config && typeof config === "object" ? cloneValue(config) : {};

    if (!next.ai || typeof next.ai !== "object")
        next.ai = {};
    if (!next.ai.models || typeof next.ai.models !== "object")
        next.ai.models = {};
    if (!next.ai.apiKeys || typeof next.ai.apiKeys !== "object")
        next.ai.apiKeys = {};
    if (!next.translator || typeof next.translator !== "object")
        next.translator = {};
    if (!next.ui || typeof next.ui !== "object")
        next.ui = {};

    var aiDefaults = defaults.ai;
    var translatorDefaults = defaults.translator;
    var uiDefaults = defaults.ui;

    next.ai.provider = typeof next.ai.provider === "string" && next.ai.provider !== "" ? next.ai.provider : aiDefaults.provider;
    next.ai.models.openai_compatible = typeof next.ai.models.openai_compatible === "string" && next.ai.models.openai_compatible !== "" ? next.ai.models.openai_compatible : aiDefaults.models.openai_compatible;
    next.ai.models.google = typeof next.ai.models.google === "string" && next.ai.models.google !== "" ? next.ai.models.google : aiDefaults.models.google;
    next.ai.temperature = Number.isFinite(Number(next.ai.temperature)) ? Number(next.ai.temperature) : aiDefaults.temperature;
    next.ai.systemPrompt = typeof next.ai.systemPrompt === "string" && next.ai.systemPrompt.trim() !== "" ? next.ai.systemPrompt : aiDefaults.systemPrompt;
    next.ai.openaiLocal = !!next.ai.openaiLocal;
    next.ai.openaiBaseUrl = typeof next.ai.openaiBaseUrl === "string" && next.ai.openaiBaseUrl.trim() !== "" ? next.ai.openaiBaseUrl.trim() : aiDefaults.openaiBaseUrl;

    next.translator.backend = typeof next.translator.backend === "string" && next.translator.backend !== "" ? next.translator.backend : translatorDefaults.backend;
    next.translator.sourceLanguage = typeof next.translator.sourceLanguage === "string" && next.translator.sourceLanguage !== "" ? next.translator.sourceLanguage : translatorDefaults.sourceLanguage;
    next.translator.targetLanguage = typeof next.translator.targetLanguage === "string" && next.translator.targetLanguage !== "" ? next.translator.targetLanguage : translatorDefaults.targetLanguage;
    next.translator.realTimeTranslation = next.translator.realTimeTranslation === undefined ? translatorDefaults.realTimeTranslation : !!next.translator.realTimeTranslation;
    next.translator.deeplApiKey = typeof next.translator.deeplApiKey === "string" ? next.translator.deeplApiKey : translatorDefaults.deeplApiKey;

    next.ui.scale = Number.isFinite(Number(next.ui.scale)) ? Number(next.ui.scale) : uiDefaults.scale;

    return next;
}

function buildGeminiCommand(endpointUrl, model, apiKey, systemPrompt, history, temperature) {
    var contents = [];

    if (systemPrompt && systemPrompt.trim() !== "") {
        contents.push({
            role: "user",
            parts: [{
                text: "System instruction: " + systemPrompt
            }]
        });
        contents.push({
            role: "model",
            parts: [{
                text: "Understood. I will follow these instructions."
            }]
        });
    }

    for (var i = 0; i < history.length; i++) {
        contents.push({
            role: history[i].role === "assistant" ? "model" : "user",
            parts: [{
                text: history[i].content
            }]
        });
    }

    var payload = {
        contents: contents,
        generationConfig: {
            temperature: temperature
        }
    };

    var finalUrl = endpointUrl.replace("{model}", model).replace("{apiKey}", apiKey);

    return {
        url: finalUrl,
        payload: JSON.stringify(payload),
        args: [
            "curl",
            "-s",
            "--no-buffer",
            "-X",
            "POST",
            "-H",
            "Content-Type: application/json",
            "-d",
            JSON.stringify(payload),
            finalUrl
        ]
    };
}

function parseGeminiStream(data) {
    if (!data)
        return null;

    var line = data.trim();
    if (line === "")
        return null;

    if (line.indexOf("data: ") === 0) {
        var jsonStr = line.slice(6).trim();
        if (jsonStr === "[DONE]")
            return { done: true };

        try {
            var json = JSON.parse(jsonStr);
            if (json.candidates && json.candidates[0] && json.candidates[0].content) {
                var parts = json.candidates[0].content.parts;
                if (parts && parts[0] && parts[0].text) {
                    return {
                        content: parts[0].text
                    };
                }
            }
        } catch (error) {
            return {
                error: "Error parsing SSE: " + error
            };
        }
    } else if (line.indexOf("{") === 0 && line.lastIndexOf("}") === line.length - 1) {
        try {
            var rawJson = JSON.parse(line);
            if (rawJson.error) {
                return {
                    error: rawJson.error.message || "API error"
                };
            }
        } catch (_ignored) {
        }
    }

    return {
        raw: line
    };
}

function buildOpenAICommand(endpointUrl, apiKey, model, systemPrompt, history, temperature) {
    var messages = [];

    if (systemPrompt && systemPrompt.trim() !== "") {
        messages.push({
            role: "system",
            content: systemPrompt
        });
    }

    for (var i = 0; i < history.length; i++) {
        messages.push(history[i]);
    }

    var payload = {
        model: model,
        messages: messages,
        temperature: temperature,
        stream: true
    };

    var args = [
        "curl",
        "-s",
        "-S",
        "--no-buffer",
        "-X",
        "POST",
        "-H",
        "Content-Type: application/json"
    ];

    if (apiKey && apiKey.trim() !== "") {
        args.push("-H");
        args.push("Authorization: Bearer " + apiKey);
    }

    args.push("-d");
    args.push(JSON.stringify(payload));
    args.push(endpointUrl);

    return {
        url: endpointUrl,
        payload: JSON.stringify(payload),
        args: args
    };
}

function parseOpenAIStream(data) {
    if (!data)
        return null;

    var line = data.trim();
    if (line === "")
        return null;

    if (line.indexOf("data: ") === 0) {
        var jsonStr = line.slice(6).trim();
        if (jsonStr === "[DONE]")
            return { done: true };

        try {
            var json = JSON.parse(jsonStr);
            if (json.choices && json.choices[0]) {
                if (json.choices[0].delta && json.choices[0].delta.content) {
                    return {
                        content: json.choices[0].delta.content
                    };
                }
                if (json.choices[0].message && json.choices[0].message.content) {
                    return {
                        content: json.choices[0].message.content
                    };
                }
            }
        } catch (error) {
            return {
                error: "Error parsing SSE JSON: " + error
            };
        }
    }

    return {
        raw: line
    };
}

function buildGoogleTranslateCommand(text, targetLang, sourceLang) {
    var url = "https://translate.google.com/translate_a/single?client=gtx"
        + "&sl=" + encodeURIComponent(sourceLang || "auto")
        + "&tl=" + encodeURIComponent(targetLang)
        + "&dt=t&q=" + encodeURIComponent(text);

    return {
        args: ["curl", "-s", url]
    };
}

function buildDeepLTranslateCommand(text, targetLang, apiKey) {
    if (!apiKey || apiKey.trim() === "") {
        return {
            error: "Please configure your DeepL API key"
        };
    }

    var host = apiKey.lastIndexOf(":fx") === apiKey.length - 3 ? "api-free.deepl.com" : "api.deepl.com";
    var url = "https://" + host + "/v2/translate";

    return {
        args: [
            "curl",
            "-s",
            "-X",
            "POST",
            url,
            "-H",
            "Authorization: DeepL-Auth-Key " + apiKey,
            "-H",
            "Content-Type: application/x-www-form-urlencoded",
            "-d",
            "text=" + encodeURIComponent(text) + "&target_lang=" + targetLang.toUpperCase()
        ]
    };
}

function parseTranslateResponse(backend, responseText) {
    if (!responseText || responseText.trim() === "") {
        return {
            error: "Empty response"
        };
    }

    try {
        if (backend === "google") {
            var response = JSON.parse(responseText);
            var result = "";
            if (response && response[0]) {
                for (var i = 0; i < response[0].length; i++) {
                    if (response[0][i] && response[0][i][0]) {
                        result += response[0][i][0];
                    }
                }
            }
            return {
                text: result
            };
        }

        if (backend === "deepl") {
            var deeplResponse = JSON.parse(responseText);
            if (deeplResponse.translations && deeplResponse.translations[0]) {
                return {
                    text: deeplResponse.translations[0].text
                };
            }
            if (deeplResponse.message) {
                return {
                    error: deeplResponse.message
                };
            }
        }
    } catch (_error) {
        return {
            error: "Failed to parse response"
        };
    }

    return {
        error: "Unknown backend or format"
    };
}
