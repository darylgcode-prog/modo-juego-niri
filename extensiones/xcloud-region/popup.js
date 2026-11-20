// Copia adaptada de xCloud Region Switcher v1.5.1, de BlaNkS01 (MIT).
// Aquí se abre como ventana propia (modo-juego xcloud region), no como globo
// de la barra: por eso recarga todas las pestañas de Xbox y luego se cierra.
const bypass=document.getElementById('bypass');
const region=document.getElementById('region'),status=document.getElementById('status'),hint=document.getElementById('hint');
const XBOX=['https://www.xbox.com/*','https://xbox.com/*','https://play.xbox.com/*'];
const fecha=t=>new Date(t).toLocaleString('es');
chrome.storage.local.get({region:'auto',bypass:false,regions:[],lastSeen:0,selection:null,selectionSeen:0,actual:null,actualSeen:0},s=>{
 bypass.checked=s.bypass;
 if(s.actual?.name){document.getElementById('actual').textContent=s.actual.name;document.getElementById('actualreason').textContent='Informada por Xbox · '+fecha(s.actualSeen);}
 for(const item of s.regions){if(!item||typeof item.name!=='string')continue;const o=document.createElement('option');o.value=item.name;o.textContent=item.name+(item.default?' (la que da Xbox)':'');region.append(o);}
 // Un ajuste guardado con el modo «más cercana» del original, que aquí no existe.
 if(s.region==='nearest')s.region='auto';
 if(s.region!=='latency'&&s.region!=='auto'&&!Array.from(region.options).some(o=>o.value===s.region)){const o=document.createElement('option');o.value=s.region;o.textContent=s.region+' (no disponible ahora)';region.append(o);}
 region.value=s.region;
 if(s.regions.length)hint.textContent='Regiones vistas en tu último inicio de sesión en Xbox Cloud'+(s.lastSeen?' ('+fecha(s.lastSeen)+').':'.');
 if(s.selection){document.getElementById('current').textContent=s.selection.name||'La que eligió Xbox (no dice cuál)';document.getElementById('reason').textContent=(s.selection.applied?'Se pidió esta región. ':'Eligió Xbox. ')+(s.selection.reason||'')+(s.selectionSeen?' · '+fecha(s.selectionSeen):'');}
});
document.getElementById('apply').addEventListener('click',()=>{
 chrome.storage.local.set({region:region.value,bypass:bypass.checked,selection:null,selectionSeen:0,actual:null,actualSeen:0},()=>{
  chrome.tabs.query({url:XBOX},tabs=>{
   const abiertas=(tabs||[]).filter(t=>t.id);
   for(const t of abiertas)chrome.tabs.reload(t.id);
   status.textContent=abiertas.length?'Guardado. Xbox Cloud se está recargando.':'Guardado. Se aplica la próxima vez que abras Xbox Cloud.';
   setTimeout(()=>window.close(),1400);
  });
 });
});
// Con mando o teclado: Escape cierra sin guardar.
document.addEventListener('keydown',e=>{if(e.key==='Escape')window.close();});
