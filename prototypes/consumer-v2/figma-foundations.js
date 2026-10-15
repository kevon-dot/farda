await figma.loadFontAsync({family:'Outfit',style:'Regular'});
await figma.loadFontAsync({family:'Outfit',style:'SemiBold'});
const page=await figma.getNodeByIdAsync('0:1');
await figma.setCurrentPageAsync(page);
const board=await figma.getNodeByIdAsync('2:58');
const created=[], variables={}, styles={}, components={}, props={};
const hex=s=>({r:parseInt(s.slice(1,3),16)/255,g:parseInt(s.slice(3,5),16)/255,b:parseInt(s.slice(5,7),16)/255});
const primitives=await createVariableCollection('Farda / Primitives',['Value']);
const colors={navy:'#142c55',deep:'#0b1d3c',blue:'#365c99',pale:'#e9eef7',cream:'#f6f5f0',muted:'#58677d',line:'#dce2eb',white:'#ffffff',amber:'#80500e',sand:'#f8ecd8'};
const raw=await createSemanticTokens(primitives.collection,primitives.modeIds,Object.entries(colors).map(([n,v])=>({name:'color/'+n,type:'COLOR',values:{Value:v},scopes:[],codeSyntax:{WEB:'var(--'+n+')'}})));
const semantic=await createVariableCollection('Farda / App',['Default']);
const aliases={'surface/canvas':'cream','surface/card':'white','surface/brand':'navy','surface/soft':'pale','surface/warm':'sand','text/primary':'navy','text/secondary':'muted','text/inverse':'white','text/warm':'amber','border/default':'line','accent/blue':'blue','surface/deep':'deep'};
const tokens=await createSemanticTokens(semantic.collection,semantic.modeIds,[...Object.entries(aliases).map(([n,p])=>({name:n,type:'COLOR',values:{Default:figma.variables.createVariableAlias(raw.variables['color/'+p])},scopes:n.startsWith('text')?['TEXT_FILL']:n.startsWith('border')?['STROKE_COLOR']:['FRAME_FILL','SHAPE_FILL'],codeSyntax:{WEB:'var(--'+n.replaceAll('/','-')+')'}})),...[4,8,12,16,20,24,32,40].map(v=>({name:'space/'+v,type:'FLOAT',values:{Default:v},scopes:['GAP'],codeSyntax:{WEB:'var(--space-'+v+')'}})),...[12,16,24,32].map(v=>({name:'radius/'+v,type:'FLOAT',values:{Default:v},scopes:['CORNER_RADIUS'],codeSyntax:{WEB:'var(--radius-'+v+')'}}))]);
Object.entries(tokens.variables).forEach(([k,v])=>variables[k]=v.id);
function paint(key){return figma.variables.setBoundVariableForPaint({type:'SOLID',color:hex(colors[aliases[key]])},'color',tokens.variables[key]);}
function fill(n,key){n.fills=[paint(key)];}
function T(parent,s,size=14,bold=false,color='text/primary'){const t=figma.createText();t.fontName={family:'Outfit',style:bold?'SemiBold':'Regular'};t.fontSize=size;t.lineHeight={unit:'PIXELS',value:Math.round(size*1.35)};t.characters=s;t.name=s;fill(t,color);parent.appendChild(t);created.push(t.id);return t;}
function F(parent,name,w,h,dir='HORIZONTAL'){const n=figma.createAutoLayout(dir);n.name=name;n.resize(w,h);n.layoutSizingHorizontal='FIXED';n.layoutSizingVertical='HUG';n.fills=[];n.itemSpacing=16;parent.appendChild(n);created.push(n.id);return n;}
for(const [name,size,line,weight] of [['Display',34,37,'SemiBold'],['Heading',26,30,'SemiBold'],['Title',18,24,'SemiBold'],['Body',14,20,'Regular'],['Body strong',14,20,'SemiBold'],['Caption',12,17,'Regular'],['Label',10,14,'SemiBold']]){const s=figma.createTextStyle();s.name='Farda/'+name;s.fontName={family:'Outfit',style:weight};s.fontSize=size;s.lineHeight={unit:'PIXELS',value:line};styles[name]=s.id;}
T(board,'Navy, warmth, and a little personality. Built from editable layers.',16);
const swatches=F(board,'Brand palette',1336,100);
for(const n of ['navy','blue','pale','cream','muted','sand']){const item=F(swatches,n,180,100,'VERTICAL');item.itemSpacing=8;const box=figma.createRectangle();box.resize(180,64);box.cornerRadius=12;box.fills=[{type:'SOLID',color:hex(colors[n])}];item.appendChild(box);created.push(box.id);T(item,n+' · '+colors[n],12);}
T(board,'Actions',22,true);
const buttons=await createComponentWithVariants({name:'Farda / Button',description:'44+ pt touch target. Label is editable. Primary actions confirm intent; answering a call never creates a dose entry.',variantAxes:{Style:['Primary','Secondary','Inverse','Outline']},baseProps:{width:240,height:48,layoutMode:'HORIZONTAL',radius:14,padding:{top:13,bottom:13,left:18,right:18}},page});
board.appendChild(buttons.componentSet);created.push(buttons.componentSet.id);
const buttonLabelKey=buttons.componentSet.addComponentProperty('Label','TEXT','Continue');
for(const c of buttons.variants){created.push(c.id);const style=c.name.split('=')[1];fill(c,style==='Primary'?'surface/brand':style==='Secondary'?'surface/soft':style==='Inverse'?'surface/canvas':'surface/card');if(style==='Outline'){c.strokes=[paint('border/default')];c.strokeWeight=1;}const t=T(c,'Continue',14,true,style==='Primary'?'text/inverse':'text/primary');const key=buttonLabelKey;t.componentPropertyReferences={characters:key};components['button'+style]=c.id;props['button'+style]=key;}
T(board,'Calendar day states',22,true);
const days=await createComponentWithVariants({name:'Farda / Calendar day',description:'Date + distinct mark, never color alone. Recorded, unconfirmed, and refill are separate concepts.',variantAxes:{State:['Default','Selected','Recorded','Unconfirmed','Refill']},baseProps:{width:44,height:44,layoutMode:'VERTICAL',radius:13,itemSpacing:4},page});
board.appendChild(days.componentSet);created.push(days.componentSet.id);
const dateKey=days.componentSet.addComponentProperty('Date','TEXT','14');
for(const c of days.variants){c.resize(44,44);c.layoutSizingHorizontal='FIXED';c.layoutSizingVertical='FIXED';created.push(c.id);let state=c.name.split('=')[1];c.fills=state==='Selected'?[paint('surface/brand')]:[];const t=T(c,'14',14,false,state==='Selected'?'text/inverse':'text/primary');const key=dateKey;t.componentPropertyReferences={characters:key};components['day'+state]=c.id;props['day'+state]=key;const mark=figma.createEllipse();mark.resize(5,5);mark.fills=state==='Unconfirmed'?[]:[paint(state==='Refill'?'text/warm':'accent/blue')];if(state==='Unconfirmed'){mark.strokes=[paint('text/secondary')];mark.strokeWeight=1;}mark.opacity=state==='Default'||state==='Selected'?0:1;c.appendChild(mark);created.push(mark.id);}
T(board,'Preference controls',22,true);
const switches=await createComponentWithVariants({name:'Farda / Switch',description:'Explicit opt-in. Off remains a first-class state.',variantAxes:{State:['On','Off']},baseProps:{width:44,height:28,layoutMode:'HORIZONTAL',radius:14,padding:{top:3,bottom:3,left:3,right:3}},page});
board.appendChild(switches.componentSet);created.push(switches.componentSet.id);
for(const c of switches.variants){c.resize(44,28);c.layoutSizingHorizontal='FIXED';c.layoutSizingVertical='FIXED';created.push(c.id);const on=c.name.endsWith('On');fill(c,on?'surface/brand':'border/default');c.primaryAxisAlignItems=on?'MAX':'MIN';const dot=figma.createEllipse();dot.resize(22,22);fill(dot,'surface/card');c.appendChild(dot);created.push(dot.id);components[on?'switchOn':'switchOff']=c.id;}
T(board,'Companion · editable vector interpretation',22,true);
const mascotSet=await createComponentWithVariants({name:'Farda / Companion',description:'Calm optional companion. No guilt, scores, or judgment. Native vector interpretation for the Figma mock; production artwork remains in the repository.',variantAxes:{Pose:['Wave','Calendar','Quiet']},baseProps:{width:120,height:120,fills:[]},page});
board.appendChild(mascotSet.componentSet);created.push(mascotSet.componentSet.id);
for(const c of mascotSet.variants){created.push(c.id);const pose=c.name.split('=')[1];const eyes=pose==='Quiet'?'<path d="M40 55q5 6 10 0M64 55q5 6 10 0" stroke="#f6f5f0" stroke-width="3" fill="none" stroke-linecap="round"/>':'<ellipse cx="45" cy="54" rx="3" ry="4.3" fill="#f6f5f0"/><ellipse cx="69" cy="54" rx="3" ry="4.3" fill="#f6f5f0"/>';
const extra=pose==='Wave'?'<path d="M91 65Q111 65 111 40" stroke="#365c99" stroke-width="14" stroke-linecap="round" fill="none"/><path d="m108 25 2-6m10 12 6-2" stroke="#80500e" stroke-width="2.5" stroke-linecap="round"/>':pose==='Calendar'?'<rect x="36" y="73" width="48" height="32" rx="6" fill="#f6f5f0"/><path d="M36 83h48M47 70v8m26-8v8" stroke="#80500e" stroke-width="3"/><path d="m49 93 6 5 11-10" stroke="#142c55" stroke-width="3" fill="none"/>':'';
const svg='<svg width="120" height="120" viewBox="0 0 120 120"><defs><linearGradient id="b" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#365c99"/><stop offset="1" stop-color="#142c55"/></linearGradient></defs><ellipse cx="60" cy="110" rx="35" ry="5" fill="#142c55" opacity=".1"/><path d="M25 72C14 43 32 15 58 15c30 0 43 25 38 52l-7 25c-3 11-19 12-25 4-7 11-21 12-27 2L25 72Z" fill="url(#b)"/><path d="M29 66Q12 75 15 87" stroke="#365c99" stroke-width="13" stroke-linecap="round" fill="none"/>'+eyes+'<path d="M52 68q6 5 12-1" stroke="#f6f5f0" stroke-width="2.5" fill="none" stroke-linecap="round"/>'+extra+'</svg>';
const art=figma.createNodeFromSvg(svg);art.name='Companion / '+pose;art.resize(120,120);c.appendChild(art);created.push(art.id,...art.findAll().map(x=>x.id));components['companion'+pose]=c.id;}
T(board,'Source mapping',22,true);T(board,'Outfit · Regular / SemiBold. Tokens map to consumer-v2/style.css.\nComponents map to Flutter widgets; native services remain separate integrations.',14);
const assetBoard=await figma.getNodeByIdAsync('2:60');
for(const id of ['2:62','2:63']){const n=await figma.getNodeByIdAsync(id);if(n)n.remove();}
T(assetBoard,'Raster upload endpoint rejected both source assets.\nThe companion here is a native vector mock. Production assets remain in the repository.',14);
return {created,mutated:[board.id,assetBoard.id],removed:['2:62','2:63'],variables,styles,components,props,collections:[primitives.collection.id,semantic.collection.id]};
