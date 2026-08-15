var websiteLoginCapture=(function(){"use strict";function T(e){return e}const g="bl-website-login-pending",c=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;function p(){if(document.getElementById("bl-website-login-overlay"))return;const e=document.createElement("style");e.id="bl-website-login-overlay-style",e.textContent=`
    @keyframes bl-login-spin { to { transform: rotate(360deg) } }
    #bl-website-login-overlay {
      position: fixed; inset: 0; z-index: 2147483647;
      display: flex; align-items: center; justify-content: center;
      background: #fff; color: #111827;
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    #bl-website-login-overlay .bl-login-content {
      display: flex; flex-direction: column; align-items: center; gap: 18px;
      padding: 32px; text-align: center;
    }
    #bl-website-login-overlay .bl-login-brand {
      font-size: 20px; font-weight: 800; letter-spacing: -0.03em;
    }
    #bl-website-login-overlay .bl-login-spinner {
      width: 30px; height: 30px; border-radius: 999px;
      border: 3px solid #e5e7eb; border-top-color: #111827;
      animation: bl-login-spin .7s linear infinite;
    }
    #bl-website-login-overlay [data-bl-login-label] {
      font-size: 15px; font-weight: 600; color: #4b5563;
    }
  `;const t=document.createElement("div");t.id="bl-website-login-overlay",t.setAttribute("role","status"),t.setAttribute("aria-live","polite"),t.innerHTML=`
    <div class="bl-login-content">
      <div class="bl-login-brand">BetterLectio</div>
      <div class="bl-login-spinner" aria-hidden="true"></div>
      <div data-bl-login-label>Logger dig ind\u2026</div>
    </div>
  `,document.documentElement.append(e,t)}const f={matches:["*://*.lectio.dk/*"],runAt:"document_start",main(){const e=window.location.href;console.log("[BetterLectio] capture@start",e);let n=new URLSearchParams(window.location.search).get("bl_login"),i=Date.now();if(!n||!c.test(n))try{const o=JSON.parse(sessionStorage.getItem(g)??"null");o?.state&&c.test(o.state)&&typeof o.createdAt=="number"&&Date.now()-o.createdAt<300*1e3&&(n=o.state,i=o.createdAt)}catch{}if(!n||!c.test(n))return;/\/lectio\/\d+\/login\.aspx$/i.test(window.location.pathname)||/\/lectio\/integration\//i.test(window.location.pathname)||p();try{sessionStorage.setItem(g,JSON.stringify({state:n,createdAt:i}))}catch{}try{const o=new URL(e);o.searchParams.delete("bl_login"),window.history.replaceState(null,"",o.toString())}catch{}console.log("[BetterLectio] captured bl_login",n.slice(0,8)+"\u2026")}};function a(e,...t){}const m={debug:(...e)=>a(console.debug,...e),log:(...e)=>a(console.log,...e),warn:(...e)=>a(console.warn,...e),error:(...e)=>a(console.error,...e)},u=globalThis.browser?.runtime?.id?globalThis.browser:globalThis.chrome;var h=class b extends Event{static EVENT_NAME=d("wxt:locationchange");constructor(t,n){super(b.EVENT_NAME,{}),this.newUrl=t,this.oldUrl=n}};function d(e){return`${u?.runtime?.id}:website-login-capture:${e}`}const w=typeof globalThis.navigation?.addEventListener=="function";function v(e){let t,n=!1;return{run(){n||(n=!0,t=new URL(location.href),w?globalThis.navigation.addEventListener("navigate",i=>{const r=new URL(i.destination.url);r.href!==t.href&&(window.dispatchEvent(new h(r,t)),t=r)},{signal:e.signal}):e.setInterval(()=>{const i=new URL(location.href);i.href!==t.href&&(window.dispatchEvent(new h(i,t)),t=i)},1e3))}}}var S=class s{static SCRIPT_STARTED_MESSAGE_TYPE=d("wxt:content-script-started");id;abortController;locationWatcher=v(this);constructor(t,n){this.contentScriptName=t,this.options=n,this.id=Math.random().toString(36).slice(2),this.abortController=new AbortController,this.stopOldScripts(),this.listenForNewerScripts()}get signal(){return this.abortController.signal}abort(t){return this.abortController.abort(t)}get isInvalid(){return u.runtime?.id==null&&this.notifyInvalidated(),this.signal.aborted}get isValid(){return!this.isInvalid}onInvalidated(t){return this.signal.addEventListener("abort",t),()=>this.signal.removeEventListener("abort",t)}block(){return new Promise(()=>{})}setInterval(t,n){const i=setInterval(()=>{this.isValid&&t()},n);return this.onInvalidated(()=>clearInterval(i)),i}setTimeout(t,n){const i=setTimeout(()=>{this.isValid&&t()},n);return this.onInvalidated(()=>clearTimeout(i)),i}requestAnimationFrame(t){const n=requestAnimationFrame((...i)=>{this.isValid&&t(...i)});return this.onInvalidated(()=>cancelAnimationFrame(n)),n}requestIdleCallback(t,n){const i=requestIdleCallback((...r)=>{this.signal.aborted||t(...r)},n);return this.onInvalidated(()=>cancelIdleCallback(i)),i}addEventListener(t,n,i,r){n==="wxt:locationchange"&&this.isValid&&this.locationWatcher.run(),t.addEventListener?.(n.startsWith("wxt:")?d(n):n,i,{...r,signal:this.signal})}notifyInvalidated(){this.abort("Content script context invalidated"),m.debug(`Content script "${this.contentScriptName}" context invalidated`)}stopOldScripts(){document.dispatchEvent(new CustomEvent(s.SCRIPT_STARTED_MESSAGE_TYPE,{detail:{contentScriptName:this.contentScriptName,messageId:this.id}})),this.options?.noScriptStartedPostMessage||window.postMessage({type:s.SCRIPT_STARTED_MESSAGE_TYPE,contentScriptName:this.contentScriptName,messageId:this.id},"*")}verifyScriptStartedEvent(t){const n=t.detail?.contentScriptName===this.contentScriptName,i=t.detail?.messageId===this.id;return n&&!i}listenForNewerScripts(){const t=n=>{!(n instanceof CustomEvent)||!this.verifyScriptStartedEvent(n)||this.notifyInvalidated()};document.addEventListener(s.SCRIPT_STARTED_MESSAGE_TYPE,t),this.onInvalidated(()=>document.removeEventListener(s.SCRIPT_STARTED_MESSAGE_TYPE,t))}};function I(){}function l(e,...t){}const E={debug:(...e)=>l(console.debug,...e),log:(...e)=>l(console.log,...e),warn:(...e)=>l(console.warn,...e),error:(...e)=>l(console.error,...e)};return(async()=>{try{const{main:e,...t}=f;return await e(new S("website-login-capture",t))}catch(e){throw E.error('The content script "website-login-capture" crashed on startup!',e),e}})()})();

websiteLoginCapture;