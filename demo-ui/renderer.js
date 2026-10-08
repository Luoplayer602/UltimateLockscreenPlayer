/* One scene renderer for lockscreen and every preview. Dimensions are logical pixels. */
(function(root) {
  'use strict';
  const {clamp}=root.ULPAudio;
  const TAU=Math.PI*2;
  const createCanvas=(w,h)=>{const c=document.createElement('canvas');c.width=w;c.height=h;return c;};
  const sample=(array,u)=>{const x=clamp(u)*(array.length-1),i=Math.floor(x);return array[i]+((array[i+1]??array[i])-array[i])*(x-i);};
  function curve(ctx,points,smooth,close=false) {
    if(!points.length)return;
    if(close && points.length>1 && points[0][0]===points.at(-1)[0] && points[0][1]===points.at(-1)[1])points=points.slice(0,-1);
    ctx.beginPath();ctx.moveTo(...points[0]);
    if(smooth && points.length>2) {
      const n=points.length,at=i=>points[close?(i+n)%n:Math.max(0,Math.min(n-1,i))];
      for(let i=0;i<(close?n:n-1);i++) {
        const a=at(i-1),b=at(i),c=at(i+1),d=at(i+2);
        ctx.bezierCurveTo(b[0]+(c[0]-a[0])/6,b[1]+(c[1]-a[1])/6,c[0]-(d[0]-b[0])/6,c[1]-(d[1]-b[1])/6,...c);
      }
    } else points.slice(1).forEach(point=>ctx.lineTo(...point));
    if(close)ctx.closePath();
  }
  function roundRect(ctx,x,y,w,h,r) {
    if(w<=0 || h<=0)return;
    r=Math.min(Math.max(0,r),w/2,h/2);
    ctx.beginPath();ctx.roundRect(x,y,w,h,r);ctx.fill();
  }
  function coverMotion(p,frame,clock) {
    const strength=Number(p.reactToBeat??.15)*(p.coverReactType==='beat'?Number(p.sensitivity??1):1),age=frame.time-frame.lastBeatAt;
    const level=p.coverReactType==='raw'?frame.raw:frame.beatPulse;
    let scale=1,x=0,y=0,rotation=0,flash=0;
    if(p.coverReactType==='raw') scale+=strength*frame.raw*.55;
    else if(frame.playing && Number.isFinite(age) && age>=0) {
      const quick=Math.exp(-age*10),slow=Math.exp(-age*5);
      const envelope=duration=>Math.sin(Math.PI*clamp(age/duration));
      switch(p.beatMotion) {
        case 'swell': scale+=strength*.6*envelope(.32);break;
        case 'flash': flash=strength*quick;break;
        case 'shake': x=strength*13*quick*Math.sin(age*95);y=strength*8*quick*Math.cos(age*79);break;
        case 'spin': scale+=strength*.45*quick;rotation=strength*.65*envelope(.48);break;
        case 'bounce': scale+=strength*.48*envelope(.8);break;
        case 'wobble': x=strength*5*slow*Math.sin(age*48);rotation=strength*.18*slow*Math.sin(age*28);break;
      }
    }
    x+=Number(p.drift||0)*25*Math.sin(clock*.63)+Number(p.rumble||0)*35*frame.raw*Math.sin(clock*47);
    y+=Number(p.drift||0)*25*Math.cos(clock*.49)+Number(p.rumble||0)*22*frame.raw*Math.cos(clock*53);
    return {scale,x,y,rotation,flash,level};
  }
  class SceneRenderer {
    constructor(canvas) {
      this.canvas=canvas;this.width=400;this.height=720;
      canvas.width=this.width;canvas.height=this.height;
      this.ctx=canvas.getContext('2d');
      this.shape=createCanvas(this.width,this.height);this.history=createCanvas(this.width,this.height);
      this.shapeContext=this.shape.getContext('2d',{willReadFrequently:true});
      this.trailPixels=this.history.getContext('2d').createImageData(this.width,this.height);
      this.background=createCanvas(this.width,this.height);this.backgroundKey='';this.artwork=null;this.coverArtwork=null;this.artworkVersion=0;
      this.palette=['#67a8ff','#bb91ff','#68d7df'];this.lastMode='';this.peaks=[];this.lastTime=null;
      const noise=createCanvas(128,128),nctx=noise.getContext('2d'),pixels=nctx.createImageData(128,128);
      for(let i=0;i<pixels.data.length;i+=4) {const v=Math.random()*255;pixels.data[i]=pixels.data[i+1]=pixels.data[i+2]=v;pixels.data[i+3]=55;}
      nctx.putImageData(pixels,0,0);this.noise=noise;
    }
    setArtwork(image,palette,coverImage=image) {this.artwork=image;this.coverArtwork=coverImage;this.artworkVersion++;if(palette)this.palette=palette;this.backgroundKey='';}
    clearHistory() {this.history.getContext('2d').clearRect(0,0,this.width,this.height);this.trailPixels.data.fill(0);this.peaks=[];}
    paint(ctx,p) {
      if(p.colourMode==='solid')return p.colour1;
      const angle=Number(p.gradientAngle||0)*Math.PI/180;
      const dx=Math.cos(angle)*170,dy=Math.sin(angle)*100;
      const grad=ctx.createLinearGradient(-dx,-dy,dx,dy);
      if(p.colourMode==='gradient') {grad.addColorStop(0,p.colour1);grad.addColorStop(1,p.colour2);}
      else {this.palette.forEach((color,i)=>grad.addColorStop(i/(this.palette.length-1),color));}
      return grad;
    }
    backgroundFrame(p) {
      const key=JSON.stringify([this.artworkVersion,p.artworkBackground,p.artworkBackgroundType,p.backgroundBlur,p.backgroundDim,p.nonArtworkBackground,p.backgroundColour1,p.backgroundColour2]);
      if(key===this.backgroundKey)return;
      this.backgroundKey=key;
      const c=this.background.getContext('2d'),w=this.width,h=this.height;
      c.clearRect(0,0,w,h);
      if(p.artworkBackground && this.artwork) {
        const image=this.artwork,iw=image.naturalWidth||image.width,ih=image.naturalHeight||image.height;
        const cover=Math.max(w/iw,h/ih),blur=p.artworkBackgroundType!=='scaled';
        c.save();
        if(blur)c.filter=`blur(${Number(p.backgroundBlur)}px)`;
        const size=cover*(blur?1+Number(p.backgroundBlur)/Math.min(w,h)*4:1);
        c.drawImage(image,(w-iw*size)/2,(h-ih*size)/2,iw*size,ih*size);c.restore();
        if(p.artworkBackgroundType==='center') {
          const fit=Math.min(w/iw,h*.64/ih);
          c.drawImage(image,(w-iw*fit)/2,(h-ih*fit)/2,iw*fit,ih*fit);
        }
        c.fillStyle=`rgba(0,0,0,${p.backgroundDim})`;c.fillRect(0,0,w,h);
      } else {
        let fill=p.backgroundColour1;
        if(p.nonArtworkBackground==='gradient') {fill=c.createLinearGradient(0,0,w,h);fill.addColorStop(0,p.backgroundColour1);fill.addColorStop(1,p.backgroundColour2);}
        c.fillStyle=fill;c.fillRect(0,0,w,h);
      }
      const shade=c.createLinearGradient(0,0,0,h);shade.addColorStop(0,'#00000018');shade.addColorStop(.6,'#00000000');shade.addColorStop(1,'#00000066');
      c.fillStyle=shade;c.fillRect(0,0,w,h);
    }
    peak(i,value,dt) {this.peaks[i]=Math.max(value,(this.peaks[i]??value)-dt*.5);return this.peaks[i];}
    drawShape(mode,p,frame,dt) {
      const c=this.shapeContext,w=this.width,h=this.height;
      c.clearRect(0,0,w,h);c.save();
      const reaction=p.visualReactType==='beat'?frame.beatPulse*Number(p.sensitivity??1):frame.raw;
      c.translate(w/2+Number(p.horizontalPosition||0),h*.42+Number(p.verticalPosition||0));
      c.rotate(Number(p.rotation||0)*Math.PI/180);
      const scale=Number(p.scale??1)*(1+Number(p.beatReaction||0)*reaction);
      c.scale(scale*Number(p.width??1)*(p.flipHorizontal?-1:1),scale*Number(p.height??1)*(p.flipVertical?-1:1));
      c.strokeStyle=c.fillStyle=this.paint(c,p);c.lineWidth=Number(p.thickness??2);c.lineJoin='round';c.lineCap='round';
      const count=Math.max(8,Math.min(128,Math.round((['bar','equalizer','dot','spectro'].includes(mode)?p.bars:p.detail)??64)));
      const plotWidth=340,maxHeight=165;
      if(['bar','equalizer','dot'].includes(mode)) {
        const slot=plotWidth/count,cell=Math.max(.25,Math.min(Number(p.barWidth)||slot,slot*(1-Number(p.spacing??.25))));
        const rows=Math.max(2,Number(p.rows??12)),rowStep=maxHeight/rows;
        for(let i=0;i<count;i++) {
          let u=i/(count-1);if(p.mirror)u=Math.abs(2*u-1);if(p.reverse)u=1-u;
          const level=Math.pow(sample(frame.spectrum,u),Number(p.dynamics??1))*(1-Number(p.edgeFade||0)*Math.abs(2*i/(count-1)-1));
          const height=Math.max(Number(p.minimumHeight??2),level*maxHeight*Number(p.barHeight??1));
          const x=-plotWidth/2+i*slot+(slot-cell)/2;
          const base=p.growFrom==='top'?-maxHeight/2:p.growFrom==='center'?0:maxHeight/2;
          const y=p.growFrom==='top'?base:p.growFrom==='center'?-height/2:base-height;
          if(mode==='bar')roundRect(c,x,y,cell,height,Number(p.cornerRadius||0));
          else {
            const active=clamp(height/maxHeight)*rows;
            for(let j=0;j<rows;j++) {
              const distance=p.growFrom==='center'?Math.max(0,Math.abs(j-(rows-1)/2)*2-(rows%2?0:1)): p.growFrom==='top'?j:rows-1-j;
              c.globalAlpha=distance<active?1:Number(p.unlitOpacity??.08);
              const size=mode==='dot'?Math.min(Number(p.dotSize)*2,cell,rowStep*.9):Math.min(cell,rowStep*.8);
              const yy=-maxHeight/2+j*rowStep+(rowStep-size)/2;
              if(mode==='dot') {c.beginPath();c.arc(x+cell/2,yy+size/2,size/2,0,TAU);c.fill();}
              else roundRect(c,x+(cell-size)/2,yy,size,size,Number(p.cornerRadius||0));
            }
            c.globalAlpha=1;
          }
          if(p.peakCaps) {
            const capH=this.peak(i,height/maxHeight,dt)*maxHeight,thickness=Number(p.capThickness??1);
            const capY=p.growFrom==='top'?base+capH+3:p.growFrom==='center'?-capH/2-3:base-capH-3;
            c.fillRect(x,capY,cell,thickness);
            if(p.growFrom==='center')c.fillRect(x,capH/2+3,cell,thickness);
          }
        }
      } else if(mode==='line') {
        const points=Array.from({length:count},(_,i)=>[-170+340*i/(count-1),-sample(frame.spectrum,i/(count-1))*80]);
        const drawLine=(sign)=>{
          const line=points.map(([x,y])=>[x,y*sign]);curve(c,line,true);c.stroke();
          if(p.fill) {c.lineTo(170,0);c.lineTo(-170,0);c.closePath();c.globalAlpha=Number(p.fillOpacity);c.fill();c.globalAlpha=1;}
        };
        drawLine(1);if(p.mirrorVertical)drawLine(-1);
      } else if(['waveform','mirror','siri'].includes(mode)) {
        const layers=mode==='siri'?3:1;
        for(let layer=layers-1;layer>=0;layer--) {
          const points=Array.from({length:count},(_,i)=>{
            const u=i/(count-1),signal=sample(frame.wave,u);
            const envelope=mode==='siri'?Math.pow(Math.sin(Math.PI*u),.65):1;
            const amplitude=signal*95*Number(p.amplitude??1)*envelope*(1-layer*.22);
            return [-170+340*u,mode==='mirror'?-Math.abs(amplitude)-Number(p.centreGap??0)/2:amplitude];
          });
          c.globalAlpha=1-layer*.25;
          if(mode==='siri' && p.colourMode==='artwork')c.strokeStyle=this.palette[layer%this.palette.length];
          curve(c,points,p.smoothCurve!==false);c.stroke();
          if(mode==='mirror') {
            const opposite=points.map(([x,y])=>[x,-y]);curve(c,opposite,true);c.stroke();
            if(p.fill) {curve(c,[...points,...opposite.reverse()],true,true);c.globalAlpha=Number(p.fillOpacity);c.fill();}
          } else if(p.fill) {c.lineTo(170,0);c.lineTo(-170,0);c.closePath();c.globalAlpha=Number(p.fillOpacity)*(1-layer*.25);c.fill();}
          c.globalAlpha=1;
        }
      } else {
        c.rotate(frame.time*Number(p.rotationSpeed||0)*Math.PI/180);
        const radius=Number((mode==='smoothSpectro'?p.size:p.innerRadius)??.38)*200;
        const segments=Math.max(1,Math.round(Number(p.symmetry??1))),points=[];
        for(let i=0;i<count;i++) {
          const turn=i/count,sector=turn*segments,part=sector%1;
          const u=segments===1?turn:Math.abs(2*part-1);
          const value=sample(frame.spectrum,u),angle=turn*TAU-Math.PI/2;
          const length=value*100*Number(p.barLength??.45);
          const r=mode==='spectro'?Math.max(1,radius+(p.growInward?-length:length)):
            radius+(mode==='circularWaveform'?sample(frame.wave,turn)*55*Number(p.amplitude??1):value*65*Number(p.reactivity??.5));
          const point=[Math.cos(angle)*r,Math.sin(angle)*r];points.push(point);
          if(mode==='spectro') {
            c.lineWidth=Number(p.barThickness??2);c.lineCap=p.roundedCaps?'round':'butt';
            if(!(p.hideVisual && p.peakCaps)) {c.beginPath();c.moveTo(Math.cos(angle)*radius,Math.sin(angle)*radius);c.lineTo(...point);c.stroke();}
            if(p.peakCaps) {
              const peak=this.peak(i,value,dt)*100*Number(p.barLength??.45);
              const rr=Math.max(1,radius+(p.growInward?-peak-4:peak+4));
              const xx=Math.cos(angle)*rr,yy=Math.sin(angle)*rr;
              c.beginPath();
              if(p.peakCapsType==='dot') {c.arc(xx,yy,Math.max(1,Number(p.barThickness)/2),0,TAU);c.fill();}
              else {const tangent=Number(p.barThickness)*1.2;c.lineWidth=1;c.moveTo(xx-Math.sin(angle)*tangent,yy+Math.cos(angle)*tangent);c.lineTo(xx+Math.sin(angle)*tangent,yy-Math.cos(angle)*tangent);c.stroke();}
            }
          }
        }
        if(mode==='spectro' && p.showInnerRing && !(p.hideVisual && p.peakCaps)) {
          c.globalAlpha=Number(p.ringOpacity);c.lineWidth=1;c.beginPath();c.arc(0,0,radius,0,TAU);c.stroke();c.globalAlpha=1;
        } else if(mode!=='spectro') {
          curve(c,[...points,points[0]],true,true);c.stroke();
          if(p.fill) {
            c.globalAlpha=Number(p.fillOpacity);
            if(mode==='circularWaveform') {c.moveTo(radius,0);c.arc(0,0,radius,0,TAU);c.fill('evenodd');}
            else c.fill();
            c.globalAlpha=1;
          }
        }
      }
      c.restore();
    }
    drawCover(p,frame,clock) {
      const c=this.ctx,m=coverMotion(p,frame,clock),radius=Number(p.coverSize??.44)*135;
      c.save();c.globalAlpha=Number(p.coverOpacity??1);
      c.translate(this.width/2+Number(p.coverX||0)+m.x,this.height*.42+Number(p.coverY||0)+m.y);
      c.rotate(m.rotation);c.scale(m.scale,m.scale);
      const halo=Number(p.coverGlow||0)+m.level*Number(p.glowPulse||0);
      c.shadowBlur=halo*35;c.shadowColor=p.outlineColour;c.fillStyle='#10131c';c.beginPath();c.arc(0,0,radius,0,TAU);c.fill();c.shadowBlur=0;
      c.save();c.beginPath();c.arc(0,0,radius,0,TAU);c.clip();
      c.rotate(frame.time*Number(p.spin||0)*Math.PI/180);
      if(p.coverMode==='artwork' && this.coverArtwork) {
        const iw=this.coverArtwork.naturalWidth||this.coverArtwork.width,ih=this.coverArtwork.naturalHeight||this.coverArtwork.height,scale=radius*2/Math.min(iw,ih);
        c.drawImage(this.coverArtwork,-iw*scale/2,-ih*scale/2,iw*scale,ih*scale);
      } else {c.fillStyle='#f5f6fb';c.textAlign='center';c.textBaseline='middle';c.font=`800 ${Math.max(9,radius*.34)}px system-ui`;c.fillText('ULP',0,1);}
      c.restore();
      if(m.flash>0) {c.fillStyle=`rgba(255,255,255,${m.flash})`;c.beginPath();c.arc(0,0,radius,0,TAU);c.fill();}
      if(Number(p.outlineThickness)>0) {c.globalAlpha*=Number(p.outlineOpacity);c.strokeStyle=p.outlineColour;c.lineWidth=Number(p.outlineThickness);c.beginPath();c.arc(0,0,radius,0,TAU);c.stroke();}
      c.restore();
    }
    render(mode,p,frame,dt=.016,enabled=true,clock=frame.time) {
      const c=this.ctx,w=this.width,h=this.height;
      if(mode!==this.lastMode || !frame.playing || (this.lastTime!==null && frame.time<this.lastTime))this.clearHistory();
      this.lastMode=mode;this.lastTime=frame.time;
      this.backgroundFrame(p);c.clearRect(0,0,w,h);c.drawImage(this.background,0,0);
      if(enabled) {
        this.drawShape(mode,p,frame,dt);
        const history=this.history.getContext('2d');
        if(Number(p.trail)>0 && frame.playing) {
          // Max-opacity history: a stationary translucent shape must never get brighter.
          const current=this.shapeContext.getImageData(0,0,w,h).data,old=this.trailPixels.data;
          const retention=Math.exp(-dt/(.04+Number(p.trail)*.85));
          for(let i=0;i<old.length;i+=4) {
            const alpha=Math.floor(old[i+3]*retention);
            if(current[i+3]>=alpha) {old[i]=current[i];old[i+1]=current[i+1];old[i+2]=current[i+2];old[i+3]=current[i+3];}
            else old[i+3]=alpha;
          }
          history.putImageData(this.trailPixels,0,0);
        } else {this.trailPixels.data.fill(0);history.clearRect(0,0,w,h);history.drawImage(this.shape,0,0);}
        c.save();c.globalAlpha=Number(p.opacity??1);c.filter=Number(p.visualBlur)>0?`blur(${p.visualBlur}px)`:'none';
        c.drawImage(this.history,0,0);
        if(Number(p.glow)>0) {c.globalAlpha*=Number(p.glow)*.32;c.filter=`blur(${2+Number(p.glow)*9}px)`;c.drawImage(this.shape,0,0);}
        c.restore();this.drawCover(p,frame,clock);
      }
      if(Number(p.grain)>0) {c.save();c.globalAlpha=Number(p.grain)*.5;c.fillStyle=c.createPattern(this.noise,'repeat');c.fillRect(0,0,w,h);c.restore();}
    }
    copyPreview(target,full=false) {
      const ctx=target.getContext('2d'),w=target.width,h=target.height;
      ctx.clearRect(0,0,w,h);ctx.fillStyle='#10131b';ctx.fillRect(0,0,w,h);
      if(full) {
        const scale=Math.min(w/this.width,h/this.height),ww=this.width*scale,hh=this.height*scale;
        ctx.drawImage(this.canvas,(w-ww)/2,(h-hh)/2,ww,hh);
      } else {
        // Close-up of the same rendered pixels; never recalculate transforms or cover state.
        const sourceHeight=this.width*h/w;
        ctx.drawImage(this.canvas,0,this.height*.42-sourceHeight/2,this.width,sourceHeight,0,0,w,h);
      }
    }
  }
  root.ULPRenderer={SceneRenderer,coverMotion,sample};
})(window);
