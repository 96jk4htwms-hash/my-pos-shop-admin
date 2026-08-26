/* SmartPOS V7.02 - optional Supabase Import Center persistence
 *
 * This module never assumes an authenticated user. If Auth is unavailable,
 * the existing local POS Import flow continues to work and the plan remains
 * in localStorage.
 */
window.SmartPOSV702SupabaseImport = (() => {
  function client(){
    return typeof window.getSupabaseClient==="function"
      ? window.getSupabaseClient()
      : null;
  }

  async function user(){
    const c=client();
    if(!c?.auth?.getUser)return null;
    const {data,error}=await c.auth.getUser();
    if(error||!data?.user)return null;
    return data.user;
  }

  async function createBatch(plan){
    const c=client(), u=await user();
    if(!c||!u)return null;

    const {data,error}=await c.from("import_batches").insert({
      owner_id:u.id,created_by:u.id,
      file_name:plan.fileName||null,
      source_type:"excel",
      schema_version:"V7.02",
      status:"PREVIEW",
      total_rows:plan.summary.total,
      new_rows:plan.summary.add,
      update_rows:plan.summary.update,
      skip_rows:plan.summary.skip,
      error_rows:plan.summary.errors,
      image_bad_rows:plan.summary.imageBad+plan.summary.imageBlocked,
      summary:plan.summary
    }).select().single();

    if(error) throw error;
    return data;
  }

  async function saveItems(batch,plan){
    if(!batch)return [];
    const c=client(),u=await user();
    if(!c||!u)return [];
    const rows=plan.items.map((x,i)=>({
      batch_id:batch.id,owner_id:u.id,row_number:i+1,
      action:x.action||"SKIP",match_type:x.matchType||null,
      matched_product_id:x.matchedProductId||null,
      name:x.name||null,code:x.code||null,size_name:x.sizeName||null,
      barcode:x.barcode||null,image_url:x.imageUrl||null,
      image_status:x.imageCheck?.status==="OK"?"OK":
        x.imageCheck?.status==="BAD"?"BAD":
        x.imageCheck?.status==="BLOCKED"?"BLOCKED":"EMPTY",
      errors:x.errors||[],warnings:x.warnings||[],diff:x.diff||[],
      raw_data:x
    }));
    const {data,error}=await c.from("import_items").insert(rows).select();
    if(error)throw error;
    return data||[];
  }

  async function finalize(batchId,status,summary){
    const c=client();
    if(!c||!batchId)return null;
    const {data,error}=await c.rpc("smartpos_finalize_import_batch",{
      p_batch_id:batchId,p_status:status,p_summary:summary||{}
    });
    if(error)throw error;
    return data;
  }

  return {createBatch,saveItems,finalize};
})();
