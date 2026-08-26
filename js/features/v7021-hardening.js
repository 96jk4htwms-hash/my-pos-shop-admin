/* SmartPOS V7.02.1 - Production hardening for the existing Import Center
 * Conservative: never silently overwrites products and never replaces a
 * working image with a URL that failed verification.
 */
(() => {
  'use strict';
  const CFG=window.SMARTPOS_V702||{};
  const U=window.SmartPOSV702Utils||{};
  const norm=U.norm||((v)=>String(v??'').trim().toLowerCase());

  function allProducts(){
    return Object.values(window.db?.products||{}).filter(p=>!p.isDeleted);
  }
  function fuzzy(row){
    const name=norm(row.name), size=norm(row.sizeName);
    if(!name) return null;
    let best=null;
    for(const p of allProducts()){
      const ns=norm(p.name);
      let score=(U.similarity?U.similarity(name,ns):0);
      if(size){
        const variants=p.variants||[];
        const vs=variants.map(v=>norm(v.sizeName)).filter(Boolean);
        if(vs.length){
          const ss=Math.max(...vs.map(x=>U.similarity?U.similarity(size,x):0));
          score=score*.78+ss*.22;
        }
      }
      if(!best||score>best.score) best={product:p,score};
    }
    return best && best.score >= Number(CFG.fuzzyThreshold||.92) ? best : null;
  }

  function applyFuzzyReview(){
    const rows=Array.isArray(window.pendingImportData)?window.pendingImportData:[];
    for(const r of rows){
      if(r.matchType && r.matchType!=='NEW' && r.matchType!=='FUZZY') continue;
      if(r.matchType==='FUZZY' && r.matchedProductId) continue;
      const m=fuzzy(r);
      if(!m) continue;
      r.matchType='FUZZY';
      r.matchedProductId=m.product.id;
      r.matchedVariantId='';
      r.warnings=Array.isArray(r.warnings)?r.warnings:[];
      r.warnings.unshift(`⚠️ พบสินค้าที่คล้ายกัน ${(m.score*100).toFixed(1)}% — ต้องตรวจสอบเองก่อน UPDATE`);
      if(!r._v7021ManualAction) r.action='SKIP';
    }
  }

  function protectBadImages(){
    const rows=Array.isArray(window.pendingImportData)?window.pendingImportData:[];
    for(const r of rows){
      const s=r.imageCheck?.status;
      if((s==='BAD'||s==='BLOCKED') && r.imageUrl){
        r.warnings=Array.isArray(r.warnings)?r.warnings:[];
        const msg=s==='BAD'?'รูปใหม่เปิดไม่ได้':'รูปใหม่ตรวจสอบไม่สำเร็จ/หมดเวลา';
        if(!r.warnings.some(x=>String(x).includes(msg))) r.warnings.push(`⚠️ ${msg} — ระบบจะไม่ทับรูปเดิมอัตโนมัติ`);
      }
    }
  }

  // Preserve manual ADD/UPDATE/SKIP decisions.
  const oldSet=window.setImportRowAction;
  if(typeof oldSet==='function'){
    window.setImportRowAction=function(rowId,action){
      const r=(window.pendingImportData||[]).find(x=>x._rowId===rowId);
      if(r) r._v7021ManualAction=true;
      return oldSet.apply(this,arguments);
    };
  }

  const oldRender=window.revalidateAndRenderImportPreview;
  if(typeof oldRender==='function'){
    window.revalidateAndRenderImportPreview=function(...args){
      const result=oldRender.apply(this,args);
      try{
        applyFuzzyReview();
        protectBadImages();
        if(typeof window.renderImportPreviewTable==='function') window.renderImportPreviewTable();
        if(window.SmartPOSV702Import?.saveLocalPlan) window.SmartPOSV702Import.saveLocalPlan();
      }catch(e){ console.warn('[V7.02.1] hardening render',e); }
      return result;
    };
  }

  async function verifyAll(){
    const rows=window.pendingImportData||[];
    if(!rows.length) return;
    if(window.SmartPOSV702Image?.verifyPendingRows){
      const btn=document.getElementById('v7021-check-images');
      if(btn) btn.disabled=true;
      try{
        await window.SmartPOSV702Image.verifyPendingRows(rows,(row)=>{
          const el=document.getElementById('v7021-image-progress');
          if(el) el.textContent=`กำลังตรวจรูป ${row._rowId||''}`;
        },{concurrency:6});
        if(typeof window.revalidateAndRenderImportPreview==='function')
          window.revalidateAndRenderImportPreview();
        const bad=rows.filter(r=>['BAD','BLOCKED'].includes(r.imageCheck?.status)).length;
        if(typeof window.showToast==='function')
          window.showToast(bad?`ตรวจรูปเสร็จ — พบ ${bad} รายการที่ต้องตรวจ`:'ตรวจรูปเสร็จ — รูปที่ตรวจพบใช้งานได้');
      }finally{
        if(btn) btn.disabled=false;
        const el=document.getElementById('v7021-image-progress');
        if(el) el.textContent='';
      }
    }
  }

  const oldConfirm=window.confirmImportData;
  if(typeof oldConfirm==='function'){
    window.confirmImportData=async function(){
      const rows=window.pendingImportData||[];
      // If images have not been checked, check them before the final commit.
      const unchecked=rows.filter(r=>r.imageUrl && (!r.imageCheck || ['checking','CHECKING'].includes(r.imageCheck.status)));
      if(unchecked.length) await verifyAll();

      const risky=rows.filter(r=>{
        const s=r.imageCheck?.status;
        return r.action!=='SKIP' && r.imageUrl && (s==='BAD'||s==='BLOCKED');
      });
      if(risky.length && typeof window.showCustomConfirm==='function'){
        return window.showCustomConfirm(
          'พบรูปที่ตรวจสอบไม่ได้',
          `มี ${risky.length} รายการที่ URL รูปใหม่ใช้ไม่ได้หรือถูกบล็อก หากกดยืนยัน ระบบจะคงรูปเดิมไว้ (ถ้ามี) และไม่ใช้ URL ที่เสีย`,
          ()=>{
            risky.forEach(r=>{ r.imageUrl=''; r.imageCheck={status:'EMPTY',reason:'รูปใหม่ไม่ผ่านการตรวจสอบ — คงรูปเดิม'}; });
            if(typeof window.revalidateAndRenderImportPreview==='function') window.revalidateAndRenderImportPreview();
            oldConfirm();
          }
        );
      }
      return oldConfirm.apply(this,arguments);
    };
  }

  // Add an explicit image-check button to the existing Import modal.
  function mountButton(){
    if(document.getElementById('v7021-check-images')) return;
    const confirm=document.getElementById('btn-confirm-import');
    if(!confirm) return;
    const wrap=confirm.parentElement;
    if(!wrap) return;
    const btn=document.createElement('button');
    btn.id='v7021-check-images';
    btn.type='button';
    btn.className='flex-1 py-4 bg-sky-100 text-sky-700 rounded-2xl font-bold shadow btn-touch text-xs';
    btn.textContent='🔍 ตรวจรูปทั้งหมด';
    btn.onclick=verifyAll;
    wrap.insertBefore(btn,confirm);
    const p=document.createElement('span');
    p.id='v7021-image-progress';
    p.className='text-[10px] text-slate-400 self-center';
    wrap.appendChild(p);
  }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',mountButton);
  else mountButton();

  // Optional: push the committed import to Supabase (import_batches/import_items) for
  // an audit trail, once the commit has actually happened — not before. We hook
  // logTransaction('PRODUCT_IMPORT', ...) rather than confirmImportData itself because
  // confirmImportData only *starts* the PIN + final-confirm modal flow; the real commit
  // (and this log entry) only happens if the user completes both steps.
  const oldLogTransaction = window.logTransaction;
  if (typeof oldLogTransaction === 'function') {
    window.logTransaction = function(action, details, opts) {
      const result = oldLogTransaction.apply(this, arguments);
      if (action === 'PRODUCT_IMPORT') {
        Promise.resolve(result).finally(() => {
          try {
            const svc = window.SmartPOSV702SupabaseImport;
            const imp = window.SmartPOSV702Import;
            if (!svc || !imp) return;
            const plan = imp.saveLocalPlan();
            svc.createBatch(plan)
              .then(batch => batch ? svc.saveItems(batch, plan).then(() => svc.finalize(batch.id, 'COMMITTED', plan.summary)) : null)
              .catch(e => console.warn('[V7.02.1] Supabase import audit skipped:', e?.message || e));
          } catch (e) { console.warn('[V7.02.1] Supabase import audit skipped:', e); }
        });
      }
      return result;
    };
  }

  window.SmartPOSV7021={
    verifyAll,
    fuzzy,
    protectBadImages
  };
})();
