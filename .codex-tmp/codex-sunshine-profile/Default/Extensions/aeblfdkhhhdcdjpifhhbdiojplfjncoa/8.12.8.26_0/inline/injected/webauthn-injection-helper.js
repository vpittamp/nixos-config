"use strict";
!function(){try{var e="undefined"!=typeof window?window:"undefined"!=typeof global?global:"undefined"!=typeof self?self:{},n=(new Error).stack;n&&(e._sentryDebugIds=e._sentryDebugIds||{},e._sentryDebugIds[n]="56ba21fe-5465-5f32-8800-6b95cfb45e6a")}catch(e){}}();

(() => {
var n=window.location.hostname.includes("dropbox")&&(window.location.pathname.includes("get")||window.location.search.includes("download_id"));window.hasWebauthnInjectionHelperRun!==!0&&!n&&o();function o(){window.hasWebauthnInjectionHelperRun=!0;let e=document.createElement("script");e.src=chrome.runtime.getURL("/inline/injected/webauthn-listeners.js"),document.documentElement.prepend(e),e.remove()}
})();

//# debugId=56ba21fe-5465-5f32-8800-6b95cfb45e6a
