/* SmartPOS V7.02.1 - image verification */
window.SmartPOSV702Image = (() => {
  async function check(url, timeoutMs = (window.SMARTPOS_V702?.imageTimeoutMs || 8000)) {
    url=String(url||"").trim();
    if(!url) return {status:"EMPTY",url:""};
    if(!/^https?:\/\//i.test(url))
      return {status:"BAD",url,reason:"URL ต้องเป็น http/https"};

    return new Promise(resolve=>{
      let finished=false;
      const img=new Image();
      const timer=setTimeout(()=>finish({status:"BLOCKED",url,reason:"หมดเวลาตรวจสอบ"}),timeoutMs);
      function finish(v){ if(finished)return; finished=true; clearTimeout(timer); resolve(v); }
      img.referrerPolicy="no-referrer";
      img.onload=()=>finish({status:"OK",url,width:img.naturalWidth,height:img.naturalHeight});
      img.onerror=()=>finish({status:"BAD",url,reason:"เปิดรูปไม่ได้"});
      img.src=url;
    });
  }

  async function verifyPendingRows(rows,onProgress,{concurrency=6}={}) {
    const list=Array.isArray(rows)?rows:[];
    let cursor=0;
    async function worker(){
      while(true){
        const i=cursor++;
        if(i>=list.length) return;
        const row=list[i];
        row.imageCheck=await check(row.imageUrl);
        if(onProgress) onProgress(row,i+1,list.length);
      }
    }
    await Promise.all(Array.from({length:Math.min(concurrency||1,Math.max(list.length,1))},worker));
    return list;
  }
  return {check,verifyPendingRows};
})();
