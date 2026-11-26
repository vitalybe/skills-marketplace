#!/usr/bin/env python3
"""Turn scan.py output into a self-contained local HTML treemap (display only, no network).
usage: treemap.py [tree.json] [-o out.html] && open out.html"""
import json, sys, html
src = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else "/tmp/free-disk-space-tree.json"
out = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else "/tmp/free-disk-space.html"
data = json.dumps(json.load(open(src))).replace("</", "<\\/")
open(out, "w").write("""<!doctype html><meta charset=utf-8><title>Disk space</title>
<style>
:root{--safe:#2e7d32;--rebuildable:#b7791f;--decide:#c62828;--protected:#4a148c;--unknown:#455a64;color-scheme:dark light}
body{margin:0;font:13px system-ui;background:#111;color:#eee}
#bar{padding:8px 12px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
#bar a{cursor:pointer;color:#8ab4f8}
#map{position:relative;height:calc(100vh - 80px);margin:0 12px}
.box{position:absolute;box-sizing:border-box;border:1px solid #111;padding:4px;overflow:hidden;cursor:pointer;color:#fff}
.box:hover{filter:brightness(1.25)}
.box b{display:block;white-space:nowrap;text-overflow:ellipsis;overflow:hidden}
.box button{position:absolute;right:3px;bottom:3px;font-size:11px;display:none}.box:hover button{display:block}
.lg span{display:inline-block;padding:1px 8px;margin-right:4px;color:#fff;border-radius:3px}
#note{padding:4px 12px;color:#aaa;min-height:1.5em}
</style>
<div id=bar></div><div id=note></div><div id=map></div>
<script>
const ROOT=""" + data + """;
const COL={safe:'--safe',rebuildable:'--rebuildable',decide:'--decide',protected:'--protected',unknown:'--unknown'};
const gib=b=>b>=2**30?(b/2**30).toFixed(1)+' GiB':(b/2**20).toFixed(0)+' MiB';
const q=s=>"'"+s.replace(/'/g,"'\\\\''")+"'";
let stack=[ROOT];
function squarify(items,x,y,w,h){ // items sorted desc by size; returns [{n,x,y,w,h}]
  const tot=items.reduce((s,i)=>s+i.size,0),res=[];let rest=items.slice();
  while(rest.length){
    const short=Math.min(w,h),area=w*h/tot;let row=[],best=Infinity,sum=0;
    for(const it of rest){
      const s2=sum+it.size,worst=Math.max(...[...row,it].map(r=>{const side=s2*area/short;const l=r.size*area/side;return Math.max(side/l,l/side)}));
      if(worst>best&&row.length)break;best=worst;row.push(it);sum=s2;
    }
    rest=rest.slice(row.length);const side=sum*area/short;
    let o=0;for(const r of row){const l=r.size*area/side;
      res.push(w>=h?{n:r,x,y:y+o,w:side,h:l}:{n:r,x:x+o,y,w:l,h:side});o+=l}
    if(w>=h){x+=side;w-=side}else{y+=side;h-=side}
    // tot shrinks as rows are consumed
    items=rest;
    if(!rest.length)break;
    return res.concat(squarify(rest,x,y,w,h));
  }
  return res;
}
function render(){
  const cur=stack[stack.length-1],map=document.getElementById('map');map.innerHTML='';
  document.getElementById('bar').innerHTML=stack.map((n,i)=>`<a onclick="stack=stack.slice(0,${i+1});render()">${i?n.name:n.path}</a>`).join(' / ')+
   ` <b>${gib(cur.size)}</b><span class=lg>`+Object.keys(COL).map(k=>`<span style="background:var(${COL[k]})">${k}</span>`).join('')+'</span>';
  document.getElementById('note').textContent=cur.note||'';
  const kids=cur.children||[];if(!kids.length){map.textContent='No larger subfolders. '+(cur.path||'');return}
  const r=map.getBoundingClientRect();
  for(const b of squarify(kids,0,0,r.width,r.height)){
    const n=b.n,d=document.createElement('div');d.className='box';
    d.style.cssText=`left:${b.x}px;top:${b.y}px;width:${b.w}px;height:${b.h}px;background:var(${COL[n.tier]||COL.unknown})`;
    d.title=`${n.path}\\n${gib(n.size)} [${n.tier}] ${n.note||''}`;
    d.innerHTML=`<b>${n.name}</b>${gib(n.size)}`;
    d.onclick=()=>{if(n.children){stack.push(n);render()}else document.getElementById('note').textContent=d.title};
    if(n.tier!=='protected'){const btn=document.createElement('button');btn.textContent='copy cmd';
      btn.onclick=e=>{e.stopPropagation();const c=n.cmd||'rm -rf -- '+q(n.path);navigator.clipboard.writeText(c);btn.textContent='copied'};d.append(btn)}
    map.append(d);
  }
}
addEventListener('resize',render);render();
</script>""")
print(out, file=sys.stderr)
