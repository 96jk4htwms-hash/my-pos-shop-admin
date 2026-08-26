const CACHE='smartpos-v7.02.2-auth-fix-2026-08-26';
const SHELL=['./','./index.html','./manifest.webmanifest','./pwa.css','./pwa-register.js','./js/core/v702-config.js','./js/core/v702-utils.js','./js/features/v702-image-checker.js','./js/features/v702-import-safety.js','./js/services/v702-supabase-import.js','./js/features/v7021-hardening.js','./js/features/v7022-docs-hub.js','./offline.html','./icons/icon-192.png','./icons/icon-512.png','./icons/icon-512-maskable.png','./icons/apple-touch-icon.png'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
 if(e.request.method!=='GET'||new URL(e.request.url).origin!==location.origin)return;
 if(e.request.mode==='navigate'){
   e.respondWith(fetch(e.request).then(r=>{caches.open(CACHE).then(c=>c.put('./index.html',r.clone()));return r}).catch(()=>caches.match('./index.html').then(r=>r||caches.match('./offline.html')))); return;
 }
 e.respondWith(caches.match(e.request).then(cached=>cached||fetch(e.request).then(r=>{if(r.ok)caches.open(CACHE).then(c=>c.put(e.request,r.clone()));return r}).catch(()=>cached)));
});
