/* SmartPOS V7.02.2 - Import Recovery + category identity hardening
 * Keeps an unfinished import draft across reloads and gives the operator a safe
 * resume/cancel choice. Uses localforage when available, localStorage fallback.
 */
(() => {
  'use strict';
  const KEY = 'smartpos_v7022_import_draft_v1';
  const safeClone = v => JSON.parse(JSON.stringify(v || []));
  const storage = {
    async get(){
      try { if (window.localforage) return await window.localforage.getItem(KEY); } catch(e){}
      try { const x = localStorage.getItem(KEY); return x ? JSON.parse(x) : null; } catch(e){ return null; }
    },
    async set(v){
      try { if (window.localforage) { await window.localforage.setItem(KEY, v); return; } } catch(e){}
      try { localStorage.setItem(KEY, JSON.stringify(v)); } catch(e){}
    },
    async clear(){
      try { if (window.localforage) await window.localforage.removeItem(KEY); } catch(e){}
      try { localStorage.removeItem(KEY); } catch(e){}
    }
  };

  let restoring = false;
  let timer = null;
  function draft(){
    const rows = window.pendingImportData;
    if (!Array.isArray(rows) || !rows.length) return null;
    return { version:1, savedAt:new Date().toISOString(), rows:safeClone(rows), headers:safeClone(window.uploadedHeaders), uploadedRows:safeClone(window.uploadedRows) };
  }
  async function save(){
    if (restoring) return;
    const d = draft();
    if (!d) return;
    clearTimeout(timer);
    timer=setTimeout(()=>storage.set(d), 150);
  }
  async function restore(){
    if (restoring) return;
    const d = await storage.get();
    if (!d?.rows?.length || !Array.isArray(window.pendingImportData)) return;
    if (window.pendingImportData.length) return;
    restoring=true;
    try {
      window.pendingImportData = d.rows;
      window.uploadedHeaders = d.headers || [];
      window.uploadedRows = d.uploadedRows || [];
      const ok = await new Promise(resolve => {
        if (typeof window.showCustomConfirm !== 'function') return resolve(true);
        window.showCustomConfirm('พบสินค้านำเข้าค้าง', `พบรายการที่ยังไม่ได้ยืนยัน ${d.rows.length} รายการ\nบันทึกล่าสุด ${new Date(d.savedAt).toLocaleString('th-TH')}`, resolve);
      });
      if (ok === false) { await storage.clear(); window.pendingImportData=[]; return; }
      window.revalidateAndRenderImportPreview?.();
      window.showToast?.(`กู้คืน Import ค้าง ${d.rows.length} รายการแล้ว`);
    } finally { restoring=false; }
  }

  window.SmartPOSImportRecovery = {
    hasDraft: () => !!draft(),
    save,
    clear: storage.clear,
    restore
  };

  // Revalidate is the common mutation point for inline edits/removals.
  const oldRevalidate = window.revalidateAndRenderImportPreview;
  if (typeof oldRevalidate === 'function') {
    window.revalidateAndRenderImportPreview = function(...args){
      const r=oldRevalidate.apply(this,args); save(); return r;
    };
  } else {
    setTimeout(()=>{
      const fn=window.revalidateAndRenderImportPreview;
      if(typeof fn==='function') window.revalidateAndRenderImportPreview=function(...args){const r=fn.apply(this,args);save();return r;};
    },500);
  }

  // A successful confirm clears the draft only after the application's commit path returns.
  const oldConfirm = window.confirmImportData;
  if (typeof oldConfirm === 'function') {
    window.confirmImportData = function(...args){
      const before = window.pendingImportData?.length || 0;
      const r = oldConfirm.apply(this,args);
      // The current application commit is synchronous inside its confirmation callback.
      setTimeout(async()=>{
        if ((window.pendingImportData?.length || 0) === before && before) return;
        if (window.pendingImportData?.length) await save();
        else await storage.clear();
      }, 500);
      return r;
    };
  }

  // On startup offer recovery after the main app has restored its DB.
  window.addEventListener('load',()=>setTimeout(restore,900));
})();
