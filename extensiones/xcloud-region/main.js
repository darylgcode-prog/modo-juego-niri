// Copia adaptada de xCloud Region Switcher v1.5.1, de BlaNkS01 (licencia MIT,
// ver LICENSE y LEEME.md). Corre dentro de la página de Xbox Cloud.
(() => {
  if (window.__xcrInstalled) return;
  Object.defineProperty(window, '__xcrInstalled', {value:true});
  const KEY='__xcr_bridge_v2';
  // Por defecto no se toca nada: elige Xbox.
  let config={region:'auto',bypass:false};
  const originalFetch=window.fetch;
  // La región real solo se da por confirmada si la respuesta de la sesión la nombra.
  const sessionUrl=url=>/^https:\/\/xgpuweb(?:f2p)?\.gssv-play-prod\.xboxlive\.com\/v\d+\/sessions\//i.test(url);
  const observeSession=async (url,response)=>{
    if(!sessionUrl(url)||!response.ok)return;
    try{
      const data=await response.clone().json();
      // No se adivina por IP, por nombre de servidor ni por la región pedida.
      const region=data?.serverRegion || data?.streamingRegion || data?.regionName || data?.session?.serverRegion;
      if(typeof region==='string' && region.length>1 && region.length<80)
        emit('actual',{name:region,source:'respuesta de la sesión de xCloud'});
    }catch(_){}
  };
  const isLogin=url => /^https:\/\/xgpuweb(?:f2p)?\.gssv-play-prod\.xboxlive\.com\/v2\/login\/user(?:[?#]|$)/i.test(url);
  // Solo se miden las direcciones por región que entrega el propio Xbox.
  // Nada de servidores de terceros ni mediciones durante el juego.
  const endpointFor = r => {
    for (const key of ['baseUri','baseUrl','endpoint','url','serviceUrl']) {
      if (typeof r[key] !== 'string') continue;
      try {
        const u = new URL(r[key]);
        if (u.protocol === 'https:' && /(?:^|\.)xboxlive\.com$/i.test(u.hostname)) return u.origin + '/';
      } catch (_) {}
    }
    return null;
  };
  const probe = async url => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 1200);
    const start = performance.now();
    try {
      // HEAD no baja el cuerpo. Una medición fallida o bloqueada se
      // descarta: no cuenta como servidor lento.
      await Reflect.apply(originalFetch, window, [url, {method:'HEAD',mode:'cors',credentials:'omit',cache:'no-store',signal:controller.signal}]);
      return Math.round(performance.now()-start);
    } catch (_) {return null;}
    finally {clearTimeout(timeout);}
  };
  const bestMeasured = async regions => {
    const candidates = regions.map(r=>({r,url:endpointFor(r)})).filter(x=>x.url).slice(0,6);
    if(candidates.length<2)return null;
    const values=await Promise.all(candidates.map(async x=>({r:x.r,ms:await probe(x.url)})));
    const good=values.filter(x=>x.ms!==null).sort((a,b)=>a.ms-b.ms);
    if(good.length<2)return null;
    return good[0];
  };
  const emit=(type,value)=>window.postMessage({channel:KEY,type,value},location.origin);
  window.addEventListener('message',e=>{
    if(e.source!==window||e.origin!==location.origin||e.data?.channel!==KEY||e.data.type!=='config')return;
    const c=e.data.value||{};
    config={region:typeof c.region==='string'?c.region:'auto',bypass:c.bypass===true};
  });
  emit('ready',null);
  window.fetch=async function(input,init){
    const url=typeof input==='string'?input:input instanceof URL?input.href:input?.url||'';
    if(!isLogin(url)){const res=await Reflect.apply(originalFetch,this,arguments);if(sessionUrl(url))void observeSession(url,res);return res;}
    let response;
    if(config.bypass){
      try {
        const request=new Request(input,init);
        const headers=new Headers(request.headers);
        headers.set('X-Forwarded-For','20.82.0.1');
        response=await Reflect.apply(originalFetch,this,[new Request(request,{headers})]);
      } catch (_) { response=await Reflect.apply(originalFetch,this,arguments); }
    } else response=await Reflect.apply(originalFetch,this,arguments);
    if(!response.ok)return response;
    try{
      const data=await response.clone().json();
      const regions=data?.offeringSettings?.regions;
      if(!Array.isArray(regions)||!regions.length)return response;
      const available=regions.filter(r=>r&&typeof r.name==='string');
      emit('regions',available.map(r=>({name:r.name,default:r.isDefault===true})));
      let measurement=null;
      if(config.region==='latency')measurement=await bestMeasured(available);
      // El original tenía además un modo «más cercana» que medía la distancia
      // desde Europa central; aquí no existe: sin medición, elige Xbox.
      const selected=config.region==='latency'?(measurement?.r||null):
        config.region==='auto'?null:available.find(r=>r.name===config.region);
      if(!selected){
        emit('selection',{name:available.find(r=>r.isDefault)?.name||'',mode:config.region,applied:false,
          reason:config.region==='latency'?'No se pudo medir ninguna región.':
                 config.region==='auto'?'':'La región guardada no vino en la lista.'});
        return response;
      }
      emit('selection',{name:selected.name,mode:config.region,applied:true,
        reason:measurement?('Respondió en unos '+measurement.ms+' ms (tiempo de respuesta web, no el retardo del juego).'):''});
      const modified={...data,offeringSettings:{...data.offeringSettings,regions:[{...selected,isDefault:true,fallbackPriority:-1}]}};
      const headers=new Headers(response.headers);
      headers.delete('content-length');headers.delete('content-encoding');
      return new Response(JSON.stringify(modified),{status:response.status,statusText:response.statusText,headers});
    }catch(_){return response;}
  };
})();
