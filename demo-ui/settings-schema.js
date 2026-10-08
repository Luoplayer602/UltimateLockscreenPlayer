// Design schema for the browser prototype. Values are stored per visual mode.
const S = (id, label, min, max, step, value, help = '') => ({id,label,type:'range',min,max,step,value,help});
const T = (id, label, value = false, help = '') => ({id,label,type:'toggle',value,help});
const P = (id, label, options, value = options[0][0], help = '') => ({id,label,type:'picker',options,value,help});
const C = (id, label, value = '#ffffff') => ({id,label,type:'color',value});
const shared = {
  colour: [
    P('colourMode','Mode',[['solid','Solid'],['gradient','Gradient'],['artwork','Artwork']],'artwork'),
    C('colour1','Colour 1'), C('colour2','Colour 2','#7cc9ff'),
    S('gradientAngle','Gradient angle',0,360,1,0),
    S('opacity','Opacity',0,1,.01,1),
    S('glow','Glow',0,1,.01,.35,'Soft light around the shape. Costs performance at high values.')
  ],
  position: [
    S('horizontalPosition','Horizontal position',-80,80,1,0), S('verticalPosition','Vertical position',-80,80,1,0),
    S('width','Width',.25,2,.01,1), S('height','Height',.25,2,.01,1),
    S('scale','Scale',.5,1.8,.01,1), S('rotation','Rotation',-180,180,1,0),
    T('flipHorizontal','Flip horizontally'), T('flipVertical','Flip vertically')
  ],
  background: [
    P('nonArtworkBackground','Non-artwork songs',[['colour','Colour'],['gradient','Gradient']],'gradient'),
    C('backgroundColour1','Colour 1','#282f47'), C('backgroundColour2','Colour 2','#714f68'),
    T('artworkBackground','Artwork background',true),
    P('artworkBackgroundType','Artwork background type',[
      ['scaled','Scaled dim image'],['center','Center dim image + blur background'],['blur','Blur background']],'blur'),
    S('backgroundDim','Dim',0,.8,.01,.4), S('backgroundBlur','Blur',0,80,1,48)
  ],
  effects: [
    S('trail','Trail',0,1,.01,0,'Keeps previous frames on screen and fades them out.'),
    S('beatReaction','Beat reaction',0,1,.01,.18,'Scales the visualizer up when a beat is detected.'),
    P('visualReactType','React to beat type', [['raw','Raw'],['beat','Beat detect']],'raw'),
    S('visualBlur','Blur',0,20,.1,0,'Softens the whole visualizer layer.'),
    S('grain','Grain',0,1,.01,0,'Adds fine noise over the finished frame.')
  ],
  cover: [
    P('coverMode','Cover mode',[['logo','Logo'],['artwork','Artwork']],'logo'),
    S('coverSize','Size',.1,1,.01,.44), S('coverX','Horizontal position',-80,80,1,0), S('coverY','Vertical position',-80,80,1,0),
    S('coverOpacity','Opacity',0,1,.01,1), S('outlineThickness','Outline thickness',0,10,.5,3),
    C('outlineColour','Outline colour','#ffffff'), S('outlineOpacity','Outline opacity',0,1,.01,.4),
    S('coverGlow','Glow',0,1,.01,.2),
    S('reactToBeat','React to beat',0,1,.01,.15,'How strongly the cover/artwork reacts on each detected beat. 0 keeps it still.'),
    P('coverReactType','React to beat type', [['raw','Raw'],['beat','Beat detect']],'beat'),
    P('beatMotion','Beat motion',[
      ['swell','Swell'],['flash','Flash'],['shake','Shake'],['spin','Spin'],['bounce','Bounce'],['wobble','Wobble']],'bounce','How it moves on a beat. Bounce springs and settles.'),
    S('rumble','Rumble',0,.2,.001,0,'A small wobble that grows with how loud the track is.'),
    S('drift','Drift',0,.2,.001,0,'A slow wander that continues regardless of the audio.'),
    S('glowPulse','Glow pulse',0,1.5,.01,0,'Swells the halo with the level.'),
    S('spin','Spin · °/s',-90,90,1,0,'Rotates the image inside its circle, like a record.')
  ],
  audio: [
    S('sensitivity','Sensitivity',0,3,.01,1,'Overall strength of the reaction.'),
    S('bass','Bass',0,2,.01,1), S('mids','Mids',0,2,.01,1), S('treble','Treble',0,2,.01,1),
    S('smoothing','Smoothing',0,1,.01,.76,'Higher settles the movement down.'),
    S('waveformSmoothing','Waveform smoothing',0,1,.01,.5,'Slows the waveform’s frame-to-frame motion.'),
    T('normalise','Normalise level',true,'Scales quiet tracks up so they still fill the frame.'),
    P('visualBand','Visual: frequency band',[
      ['drum','Drum'],['bass','Bass'],['mid','Mids'],['high','Treble'],['full','Full']],'full'),
    P('zoomBand','Zoom: frequency band',[
      ['drum','Drum'],['bass','Bass'],['mid','Mids'],['high','Treble'],['full','Full']],'bass'),
    S('beatSensitivity','Beat sensitivity',.5,2,.05,1,'Higher detects smaller attacks; lower rejects more weak transients.'),
    S('beatInterval','Minimum beat interval · s',.12,.5,.01,.2,'Minimum time between two detected hits.'),
    S('beatRelease','Beat release · s',.08,.6,.01,.2,'How quickly the visualizer settles after a detected hit.'),
    S('fps','FPS tối đa',15,60,5,60)
  ]
};
const bar = [
  S('bars','Bars',8,128,1,32), S('barWidth','Bar width',0,24,.5,0,'A cap on each bar’s width. 0 sizes bars automatically.'),
  S('spacing','Spacing',0,.9,.01,.25,'Share of each slot used as a gap between bars.'),
  S('barHeight','Bar height',0,2,.01,1,'Scales how tall the bars grow.'),
  S('cornerRadius','Corner radius',0,12,.5,1),
  S('frequencyRange','Frequency range',0,1,.01,1,'Lower values focus on bass and low mids.'),
  T('mirror','Mirror',true,'Reflects the spectrum about the centre, so bass meets in the middle.'),
  T('reverse','Reverse',false,'Swaps the frequency order.'),
  S('edgeFade','Edge fade',0,1,.01,0,'Tapers the bars towards the edges.'),
  P('growFrom','Grow from',[['bottom','Bottom'],['center','Center'],['top','Top']],'bottom'),
  S('minimumHeight','Minimum height · px',0,12,.5,2,'Keeps a visible baseline during quiet passages.'),
  S('dynamics','Dynamics',.2,3,.01,1,'Above 1 leaves occasional spikes; below 1 fills the frame.'),
  T('peakCaps','Peak caps'), S('capThickness','Cap thickness · px',.5,8,.5,1)
];
const modeSpecs = {
  bar: {family:'SPECTRUM',label:'Bar',fields:bar},
  equalizer: {family:'SPECTRUM',label:'Equalizer',detail:'Ma trận ô vuông',fields:[...bar,S('rows','Rows',2,32,1,16),S('unlitOpacity','Unlit opacity',0,1,.01,.08)]},
  line: {family:'SPECTRUM',label:'Line',fields:[S('detail','Detail',12,128,1,64),S('thickness','Thickness',.5,12,.5,2),bar[5],T('fill','Fill under curve'),S('fillOpacity','Fill opacity',0,1,.01,.2),T('mirrorVertical','Mirror vertically')]},
  dot: {family:'SPECTRUM',label:'Dot',detail:'Ma trận chấm tròn',fields:[S('bars','Bars',8,128,1,24),S('rows','Rows',2,32,1,12),S('dotSize','Dot size',1,12,.5,4),bar[5],S('unlitOpacity','Unlit opacity',0,1,.01,.08),P('growFrom','Grow from',[['bottom','Bottom'],['center','Centre']],'bottom')]},
  waveform: {family:'WAVEFORM',label:'Waveform',help:'The classic horizontal wave. Reads clearly at small sizes.',fields:[S('thickness','Thickness',.5,12,.5,3),S('amplitude','Amplitude',0,2,.01,1,'How far the wave travels from its centre line.'),S('detail','Detail',12,128,1,64,'More detail shows finer movement.'),T('smoothCurve','Smooth curve',true),T('fill','Fill under wave'),S('fillOpacity','Fill opacity',0,1,.01,.2)]},
  mirror: {family:'WAVEFORM',label:'Mirror',fields:[S('thickness','Thickness',.5,12,.5,3),S('amplitude','Amplitude',0,2,.01,1),S('detail','Detail',12,128,1,64),S('centreGap','Centre gap',0,80,1,12),T('fill','Fill'),S('fillOpacity','Fill opacity',0,1,.01,.2)]},
  siri: {family:'WAVEFORM',label:'Siri',fields:[S('thickness','Thickness',.5,12,.5,3),S('amplitude','Amplitude',0,2,.01,1),S('detail','Detail',12,128,1,64),T('smoothCurve','Smooth curve',true),T('fill','Fill under wave'),S('fillOpacity','Fill opacity',0,1,.01,.2)]},
  spectro: {family:'CIRCULAR',label:'Spectro',detail:'Vòng thanh phổ',fields:[S('bars','Bars',12,128,1,64),S('innerRadius','Inner radius',.1,.8,.01,.38,'Size of the empty circle in the middle.'),S('barLength','Bar length',0,1,.01,.45),S('barThickness','Bar thickness',.5,12,.5,2),S('rotationSpeed','Rotation speed · °/s',-90,90,1,0),bar[5],S('symmetry','Symmetry',1,12,1,1,'Mirrors the spectrum into this many segments.'),T('growInward','Grow inward'),T('roundedCaps','Rounded caps',true),T('showInnerRing','Show inner ring',true),S('ringOpacity','Ring opacity',0,1,.01,.4),T('peakCaps','Peak caps'),P('peakCapsType','Peak caps type',[['line','Line'],['dot','Dot']]),T('hideVisual','Hide visualizer but peak caps')]},
  circularWaveform: {family:'CIRCULAR',label:'Circular waveform',fields:[S('detail','Detail',12,128,1,64),S('innerRadius','Inner radius',.1,.8,.01,.38),S('amplitude','Amplitude',0,2,.01,1),S('thickness','Thickness',.5,12,.5,3),S('rotationSpeed','Rotation speed · °/s',-90,90,1,0),T('fill','Fill ring'),S('fillOpacity','Fill opacity',0,1,.01,.2)]},
  smoothSpectro: {family:'CIRCULAR',label:'Smooth spectro',fields:[S('detail','Detail',12,128,1,64),S('symmetry','Symmetry',1,12,1,1),S('size','Size',.1,1,.01,.42),S('reactivity','Reactivity',0,2,.01,.5,'How far the ring bulges out on strong frequencies.'),S('thickness','Thickness',.5,12,.5,3),S('rotationSpeed','Rotation speed · °/s',-90,90,1,0),bar[5],T('fill','Fill'),S('fillOpacity','Fill opacity',0,1,.01,.2)]}
};
