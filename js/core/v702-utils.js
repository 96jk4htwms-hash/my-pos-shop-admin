/* SmartPOS V7.02 - safe utilities */
window.SmartPOSV702Utils = (() => {
  const norm = v => String(v ?? "").trim().toLowerCase()
    .normalize("NFKC").replace(/\s+/g, " ");

  const num = v => {
    if (v === "" || v === null || v === undefined) return null;
    const n = Number(String(v).replace(/,/g, "").replace(/[฿$]/g, "").trim());
    return Number.isFinite(n) ? n : null;
  };

  const uid = (prefix="sp") =>
    `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2,10)}`;

  const escapeHTML = v => String(v ?? "").replace(/[&<>"']/g, c =>
    ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" })[c]);

  const similarity = (a,b) => {
    a=norm(a); b=norm(b);
    if (!a || !b) return 0;
    if (a===b) return 1;
    const prev=Array.from({length:b.length+1},(_,i)=>i);
    for(let i=1;i<=a.length;i++){
      let cur=[i];
      for(let j=1;j<=b.length;j++){
        cur[j]=Math.min(cur[j-1]+1,prev[j]+1,prev[j-1]+(a[i-1]===b[j-1]?0:1));
      }
      for(let j=0;j<prev.length;j++) prev[j]=cur[j];
    }
    return 1-prev[b.length]/Math.max(a.length,b.length);
  };

  return {norm,num,uid,escapeHTML,similarity};
})();
