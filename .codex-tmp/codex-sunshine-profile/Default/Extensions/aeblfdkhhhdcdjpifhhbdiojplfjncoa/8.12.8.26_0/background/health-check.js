"use strict";
!function(){try{var e="undefined"!=typeof window?window:"undefined"!=typeof global?global:"undefined"!=typeof self?self:{},n=(new Error).stack;n&&(e._sentryDebugIds=e._sentryDebugIds||{},e._sentryDebugIds[n]="70bc2cb0-418e-58c1-b917-3822c75dbe8d")}catch(e){}}();

(() => {
chrome.runtime.onMessage.addListener((r,e,a)=>{r.name==="health-check-request"&&(console.info("[Background]","HealthCheck: received request from tab "+e.tab?.id)||chrome.runtime[Symbol.for("com.1password.logger")]?.report(["HealthCheck: received request from tab "+e.tab?.id],{severity:"info",fileName:"js/b5x/background/src/background/health-check.ts",lineNumber:17,srcLineNumber:9,prefix:"[Background]",highlight:!1,rawParams:'"HealthCheck: received request from tab " + sender.tab?.id'}),a({name:"health-check-response",data:"alive"}))});
})();

//# debugId=70bc2cb0-418e-58c1-b917-3822c75dbe8d
