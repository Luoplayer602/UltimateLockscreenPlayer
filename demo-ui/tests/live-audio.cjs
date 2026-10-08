// Run with Windows Node while a dedicated Chrome uses --remote-debugging-port=9224.
const fs=require('node:fs');
(async()=>{
 const tabs=await(await fetch('http://127.0.0.1:9224/json')).json();
 const tab=tabs.find(t=>t.type==='page'&&t.url.startsWith('http://localhost:8765/'));
 if(!tab)throw Error('Open the demo in the dedicated test Chrome first.');
 const ws=new WebSocket(tab.webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));
 let id=0;const pending=new Map(),errors=[];
 ws.addEventListener('message',event=>{const message=JSON.parse(event.data);if(message.method==='Runtime.exceptionThrown')errors.push(message.params.exceptionDetails.text);if(message.id){const cb=pending.get(message.id);pending.delete(message.id);message.error?cb.reject(message.error):cb.resolve(message.result);}});
 const call=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
 await call('Runtime.enable');await call('Page.enable');await call('Emulation.setDeviceMetricsOverride',{width:1200,height:940,deviceScaleFactor:1,mobile:false});
 await call('Page.navigate',{url:'http://localhost:8765/?test'});await new Promise(r=>setTimeout(r,1500));
 console.log('initial',await evaluate('({duration:audio.duration,readyState:audio.readyState})'));
 await evaluate(`(async()=>{design.mode='waveform';const p=profile();p.coverMode='logo';p.amplitude=1;p.scale=1;p.sensitivity=1;p.visualReactType='beat';p.coverReactType='beat';p.reactToBeat=.6;p.trail=.7;syncDesign();window.renderTimes=[];const originalRender=sceneRenderer.render.bind(sceneRenderer);sceneRenderer.render=(...args)=>{const t=performance.now();originalRender(...args);renderTimes.push(performance.now()-t);};audio.currentTime=0;if(audio.paused)await togglePlayback();window.liveSamples=[];window.liveTimer=setInterval(()=>liveSamples.push({time:audio.currentTime,rms:lastAudioFrame.rms,wave:Math.max(...lastAudioFrame.wave.map(Math.abs)),beatCount:lastAudioFrame.beatCount}),250);return true;})()`);
 await new Promise(r=>setTimeout(r,6500));
 const result=await evaluate('(()=>{clearInterval(liveTimer);return {samples:liveSamples,context:audioContext.state,source:audio.currentSrc,playing:!audio.paused,renderTimes}})()');
 if(!result.playing||result.context!=='running'||!result.samples.some(x=>x.rms>.001&&x.wave>.001))throw Error('Live audio did not reach the analysis/render pipeline: '+JSON.stringify(result));
 console.log(JSON.stringify({samples:result.samples.length,first:result.samples[0],last:result.samples.at(-1),maxRms:Math.max(...result.samples.map(x=>x.rms)),maxWave:Math.max(...result.samples.map(x=>x.wave)),renderP95ms:result.renderTimes.sort((a,b)=>a-b)[Math.floor(result.renderTimes.length*.95)],runtimeErrors:errors}));
 await evaluate("if(settingsScreen.hidden)fakeHome.click();setPage('visualizer')");
 const shot=await call('Page.captureScreenshot',{format:'png'});
 if(process.argv[2])fs.writeFileSync(process.argv[2],Buffer.from(shot.data,'base64'));
 await evaluate('audio.pause()');ws.close();
 if(errors.length)throw Error(errors.join('\n'));
})().catch(error=>{console.error(error);process.exitCode=1;});
