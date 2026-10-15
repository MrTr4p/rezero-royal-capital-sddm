import RFB from './vendor/novnc/core/rfb.js';
const screen = document.querySelector('#screen');
const loading = document.querySelector('#loading');
const notice = document.querySelector('#notice');
let noticeTimer;
function notify(message) { clearTimeout(noticeTimer); notice.textContent=message; notice.style.display='block'; noticeTimer=setTimeout(()=>notice.style.display='none',2600); }
try {
  let config;
  for(let attempt=0;attempt<60;attempt++) {
    try {
      const response=await fetch('/api/status');
      if(response.ok) config=await response.json();
      if(config?.ready) break;
    } catch { /* The service may still be starting its isolated display. */ }
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  if(!config?.ready) throw new Error('The local preview is still starting. Reload in a moment.');
  const wallpaper=document.querySelector('#wallpaper'), motion=document.querySelector('#motion'), reset=document.querySelector('#reset');
  for(const item of config.wallpapers) wallpaper.add(new Option(item.label,item.id));
  let selectedWallpaper=config.wallpaper, selectedMotion=config.motion;
  wallpaper.value=selectedWallpaper; motion.value=selectedMotion;
  wallpaper.disabled=false; motion.disabled=false;
  const rfb=new RFB(screen,`ws://127.0.0.1:${config.websocketPort}`,{shared:true});
  rfb.scaleViewport=true; rfb.resizeSession=false; rfb.background='#f2efe7';
  rfb.qualityLevel=8; rfb.compressionLevel=2;
  rfb.addEventListener('connect',()=>{loading.classList.add('hidden');rfb.focus();});
  rfb.addEventListener('disconnect',()=>{loading.classList.remove('hidden');loading.querySelector('small').textContent='Preview disconnected. Reload to reconnect.';});
  async function changePreview(endpoint,body,message) {
    wallpaper.disabled=true; motion.disabled=true; reset.disabled=true;
    try {
      const result=await fetch(endpoint,{method:'POST',headers:{'X-Preview-Action':'1','Content-Type':'application/json'},body:JSON.stringify(body)});
      if(!result.ok) throw new Error('Could not update the preview.');
      const state=await result.json(); selectedWallpaper=state.wallpaper; selectedMotion=state.motion;
      notify(message);
    } catch(error) {notify(error.message);}
    finally {
      wallpaper.value=selectedWallpaper; motion.value=selectedMotion;
      wallpaper.disabled=false; motion.disabled=false; reset.disabled=false; rfb.focus();
    }
  }
  wallpaper.onchange=()=>changePreview('/api/wallpaper',{wallpaper:wallpaper.value},`${wallpaper.selectedOptions[0].textContent} selected.`);
  motion.onchange=()=>changePreview('/api/motion',{motion:motion.value},`${motion.selectedOptions[0].textContent} motion selected.`);
  reset.onclick=()=>changePreview('/api/reset',{},'Theme reset.');
  document.querySelector('#fullscreen').onclick=async()=>{
    try {if(document.fullscreenElement)await document.exitFullscreen();else await document.documentElement.requestFullscreen();}
    catch{notify('Full screen is unavailable in this browser.');}
    rfb.focus();
  };
  window.previewRfb=rfb;
} catch(error) {loading.querySelector('small').textContent=error.message;}
