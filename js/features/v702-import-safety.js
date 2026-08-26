/* SmartPOS V7.02 - Import Safety bridge
 *
 * Works with the existing V7.01 inline Import Center instead of replacing it.
 * Adds:
 *  - stronger duplicate index
 *  - URL/image verification
 *  - field-level decisions
 *  - local recovery plan
 *  - optional Supabase import audit
 */
(() => {
  const U=window.SmartPOSV702Utils;
  const CFG=window.SMARTPOS_V702;

  function products(){
    return Object.values(window.db?.products||{});
  }

  function buildIndex(){
    const idx={barcode:new Map(),code:new Map(),nameSize:new Map()};
    for(const p of products()){
      const code=U.norm(p.code);
      if(code) idx.code.set(code,p);
      for(const v of (p.variants||[])){
        const bc=U.norm(v.barcode);
        const ns=`${U.norm(p.name)}|${U.norm(v.sizeName)}`;
        if(bc) idx.barcode.set(bc,{product:p,variant:v});
        idx.nameSize.set(ns,{product:p,variant:v});
      }
    }
    return idx;
  }

  function analyzeRow(row, index=buildIndex()){
    const bc=U.norm(row.barcode), code=U.norm(row.code);
    const ns=`${U.norm(row.name)}|${U.norm(row.sizeName)}`;
    if(bc && index.barcode.has(bc))
      return {type:"BARCODE",match:index.barcode.get(bc),confidence:1};
    if(code && index.code.has(code))
      return {type:"CODE",match:{product:index.code.get(code)},confidence:1};
    if(index.nameSize.has(ns))
      return {type:"NAME_SIZE",match:index.nameSize.get(ns),confidence:.98};

    let best=null;
    for(const p of products()){
      const score=U.similarity(row.name,p.name);
      if(!best||score>best.confidence) best={type:"FUZZY",match:{product:p},confidence:score};
    }
    return best && best.confidence>=CFG.fuzzyThreshold ? best : {type:"NEW",match:null,confidence:0};
  }

  function localPlan(){
    const rows=Array.isArray(window.pendingImportData)?window.pendingImportData:[];
    return {
      version:CFG.version,
      schemaVersion:CFG.schemaVersion,
      createdAt:new Date().toISOString(),
      fileName:window.uploadedFileName||window.currentImportFileName||"",
      summary:{
        total:rows.length,
        add:rows.filter(r=>r.isValid&&r.action==="ADD").length,
        update:rows.filter(r=>r.isValid&&r.action==="UPDATE").length,
        skip:rows.filter(r=>r.action==="SKIP").length,
        errors:rows.filter(r=>!r.isValid).length,
        imageBad:rows.filter(r=>r.imageCheck?.status==="BAD").length,
        imageBlocked:rows.filter(r=>r.imageCheck?.status==="BLOCKED").length
      },
      items:rows.map(r=>({
        rowId:r._rowId,rowNumber:r._rowId,
        action:r.action,matchType:r.matchType,
        matchedProductId:r.matchedProductId||null,
        matchedVariantId:r.matchedVariantId||null,
        name:r.name,code:r.code,sizeName:r.sizeName,barcode:r.barcode,
        imageUrl:r.imageUrl||"",
        imageCheck:r.imageCheck||null,
        diff:r.diff||[],
        errors:r.errors||[],
        warnings:r.warnings||[]
      }))
    };
  }

  function saveLocalPlan(){
    const plan=localPlan();
    try{localStorage.setItem(CFG.localPlanKey,JSON.stringify(plan));}catch(e){}
    return plan;
  }

  function getLocalPlan(){
    try{return JSON.parse(localStorage.getItem(CFG.localPlanKey)||"null");}
    catch(e){return null;}
  }

  async function verifyImages(){
    if(!Array.isArray(window.pendingImportData)) return [];
    const result=await SmartPOSV702Image.verifyPendingRows(window.pendingImportData,(row)=>{
      if(typeof window.revalidateAndRenderImportPreview==="function")
        window.revalidateAndRenderImportPreview();
    });
    saveLocalPlan();
    return result;
  }

  function addFieldDecision(rowId,field,decision){
    const row=(window.pendingImportData||[]).find(r=>r._rowId===rowId);
    if(!row)return false;
    if(!row.fieldActions)row.fieldActions={};
    if(!["APPLY","SKIP"].includes(decision))return false;
    row.fieldActions[field]=decision;
    saveLocalPlan();
    return true;
  }

  // Expose explicit APIs for the new UI without replacing V7.01.
  window.SmartPOSV702Import={
    buildIndex,analyzeRow,localPlan,saveLocalPlan,getLocalPlan,
    verifyImages,addFieldDecision
  };

  // Keep a recovery plan whenever the existing preview changes.
  const oldRender=window.revalidateAndRenderImportPreview;
  if(typeof oldRender==="function"){
    window.revalidateAndRenderImportPreview=function(...args){
      const result=oldRender.apply(this,args);
      try{saveLocalPlan();}catch(e){}
      return result;
    };
  }
})();
