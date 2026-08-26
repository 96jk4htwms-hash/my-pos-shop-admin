(()=>{let deferred=null;const s=document.createElement('div');s.id='pwa-status';document.body.appendChild(s);
const b=document.createElement('button');b.id='pwa-install';b.textContent='📲 ติดตั้ง Smart POS';document.body.appendChild(b);
const show=m=>{s.textContent=m;s.classList.add('show')},hide=()=>s.classList.remove('show');
addEventListener('online',()=>{show('🟢 กลับมาออนไลน์แล้ว');setTimeout(hide,2200)});
addEventListener('offline',()=>show('🟠 ออฟไลน์ — การซิงค์จะทำเมื่อกลับมาออนไลน์'));
addEventListener('beforeinstallprompt',e=>{e.preventDefault();deferred=e;b.classList.add('show')});
b.onclick=async()=>{if(!deferred)return;deferred.prompt();try{await deferred.userChoice}catch(_){}deferred=null;b.classList.remove('show')};
addEventListener('appinstalled',()=>{deferred=null;b.classList.remove('show');show('✅ ติดตั้ง Smart POS แล้ว');setTimeout(hide,3000)});
if('serviceWorker' in navigator)addEventListener('load',()=>navigator.serviceWorker.register('./sw.js').catch(e=>console.warn('[PWA]',e)));
if(/iphone|ipad|ipod/i.test(navigator.userAgent)&&/safari/i.test(navigator.userAgent)&&!matchMedia('(display-mode:standalone)').matches)
setTimeout(()=>{show('📲 iPad/iPhone: กด แชร์ → เพิ่มไปยังหน้าจอโฮม');setTimeout(hide,7000)},1800);
})();