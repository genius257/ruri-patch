#!/usr/bin/env bash
# replace_with_uwu.sh
# Replaces  =["Accomplishing" … "Wrangling"];  with the minified UwU list.

set -euo pipefail

# ----- USER-ADJUSTABLE SETTINGS ---------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLD_DIR=$(ls -d "$HOME"/.vscode/extensions/anthropic.claude-code-*-win32-x64 2>/dev/null | sort -V | tail -n1)

TARGET_FILE="${CLD_DIR}/webview/index.js"   # file to patch
CSS_FILE="${CLD_DIR}/webview/index.css"       # CSS file to patch
UWLIST_FILE="${SCRIPT_DIR}/uwu_list.json"  # minified JSON array, one line
NEW_SVG_FILE="${SCRIPT_DIR}/ruri.svg"
TIPS_FILE="${SCRIPT_DIR}/kawaii_tips.json"  # flat JSON string array; [[Key]] -> keycap
# ---------------------------------------------------------------------------

[[ -n "$CLD_DIR" && -f "$TARGET_FILE" && -f "$CSS_FILE" ]] || { echo "claude-code extension not found under ~/.vscode/extensions" >&2; exit 1; }

# Make a time-stamped backup
cp -- "$TARGET_FILE" "${TARGET_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
cp -- "$CSS_FILE" "${CSS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"

# 1) Load the minified array (strip any stray newlines just in case)
uwu_list=$(tr -d '\n' < "$UWLIST_FILE")

# 2) Cute 6-frame and 10-frame spinners
kawaii_6='["💗","💕","💖","✨","🌟","💫"]'
kawaii_10='["💗","💕","💖","✨","🌟","💫","🌟","✨","💖","💕"]'

# helper to escape for sed
escape() { printf '%s' "$1" | sed 's/[\/&]/\\&/g'; }

# --- patch reporting -------------------------------------------------------
# ✓ if needle present, ✗ if not  (-F = fixed string: safe for emoji/brackets)
check()      { grep -qF -- "$2" "$1" && echo "  ✓ $3" || echo "  ✗ $3 — NOT patched"; }
# inverse: success means the source anchor is gone (was replaced)
check_gone() { grep -qF -- "$2" "$1" && echo "  ✗ $3 — anchor still present" || echo "  ✓ $3"; }

# Build the sed expression:
#   1. Replace the opening  =["Accomplishing"  with  =[ + $uwu_list
#   2. Replace the closing  "Wrangling"];      with  ];
sed -i -E \
    -e "s|=\[ *\"Accomplishing\"[^]]*\"Wrangling\" *]|=[$uwu_list]|g" \
    -e "s|=\[ *\"·\"[^]]*\"✽\" *]|=$(escape "$kawaii_6")|g" \
    -e "s|=\[ *\"·\"[^]]*\"✢\" *]|=$(escape "$kawaii_10")|g" \
    "$TARGET_FILE"

echo "Patches:"
check_gone "$TARGET_FILE" 'Accomplishing' "task word list"
check_gone "$TARGET_FILE" '✽'            "6-frame spinner"
check_gone "$TARGET_FILE" '✢'            "10-frame spinner"

# 3) Replace the logo <svg> (single path) with the custom multi-path SVG.
#    Injected as dangerouslySetInnerHTML — one string, not 2278 React path calls.
#    Anchors on the logo's `d` data + backrefs the minified helper name, so it
#    survives version bumps. Idempotent: no-op once patched.
perl - "$TARGET_FILE" "$NEW_SVG_FILE" <<'PERL'
my ($target, $svgfile) = @ARGV;
my $svg = do { open my $f,'<:raw',$svgfile or die "$svgfile: $!"; local $/; <$f> };
my ($vb)   = $svg =~ /<svg\b[^>]*?viewBox="([^"]*)"/i; $vb //= "0 0 1024 1024";
my ($open) = $svg =~ /(<svg\b[^>]*>)/i;
my $inner = $svg;
$inner =~ s/^.*?\Q$open\E//s;   # drop up to and incl. opening <svg ...>
$inner =~ s{</svg>.*$}{}s;       # drop closing </svg> onward
$inner =~ s/^\s+|\s+$//g;
$inner =~ s/\\/\\\\/g; $inner =~ s/"/\\"/g; $inner =~ s/\r?\n\s*/ /g;  # -> JS string
my $c = do { open my $f,'<:raw',$target or die "$target: $!"; local $/; <$f> };
my $n = ($c =~ s{([A-Za-z_\$][\w\$]*)\("svg",\{([^{}]*?)children:\1\("path",\{[^{}]*?d:"M5\.08191 10\.0769[^"]*"[^{}]*\}\)\}\)}{
  my ($h, $p) = ($1, $2);
  $p =~ s/viewBox:"[^"]*"/qq(viewBox:"$vb")/e;
  $h.'("svg",{'.$p.'dangerouslySetInnerHTML:{__html:"'.$inner.'"}})'
}ge);
print "  – logo svg — anchor not found (already patched or logo changed)\n" and exit 0 if $n == 0;
open my $out,'>:raw',$target or die "$target: $!"; print $out $c;
print "  ✓ logo svg\n";
PERL

# 4) Replace the "before first message" tip texts with kawaii versions.
#    Tips file is a flat JSON string array; the script builds the {text:…}
#    objects. A [[Key]] token becomes a real keycap element — the minified
#    helper/style names it needs (jsx b, jsxs E, Fragment, styles var, .key,
#    .keyboardShortcut) are SCRAPED from the bundle, never hard-coded, so
#    keycaps survive version bumps. No keycap in a future build -> plain text.
#    The heterogeneous array (strings + elements) can't be sed'd, so we locate
#    it by string-aware balanced-bracket scan and splice the whole literal.
tips_json=$(tr -d '\n' < "$TIPS_FILE")
perl - "$TARGET_FILE" "$tips_json" <<'PERL'
my ($target, $json) = @ARGV;
my $c = do { open my $f,'<:raw',$target or die "$target: $!"; local $/; <$f> };

# -- scrape the keycap identifiers from an existing keycap tip --------------
#    Match the shortcut-div + its first key-span together (span's styles var
#    tied to the div's via \2) so we get the keycap-specific names, not some
#    unrelated span. E=jsxs helper, SV=styles obj, CSHORT/CKEY=class keys, B=jsx.
my $CSHORT = "keyboardShortcut";   # CSS-module property name (semantic, stable)
my ($E,$SV,$B,$CKEY) =
  $c =~ /(\w+)\("div",\{className:(\w+)\.keyboardShortcut,children:\[(\w+)\("span",\{className:\2\.(\w+),children:"/;
my ($FRAG) = defined($E) ? ($c =~ /\Q$E\E\(([A-Za-z_\$]\w*),\{children:\[/) : ();
my $keycaps = defined($E)&&defined($SV)&&defined($B)&&defined($CKEY)&&defined($FRAG);

# -- build the {text:…} objects from the flat string list -------------------
my @strings = $json =~ /"([^"]*)"/g;   # each JSON string's inner content (tips must not embed a literal ")
die "no tip strings in tips file\n" unless @strings;
my @objs;
for my $s (@strings) {
  if ($s !~ /\[\[/) { push @objs, '{text:"'.$s.'"}'; next; }
  unless ($keycaps) { (my $t=$s) =~ s/\[\[(.*?)\]\]/$1/g; push @objs, '{text:"'.$t.'"}'; next; }
  my (@ch, @caps);
  my $flush = sub { return unless @caps;
    push @ch, '" "', $E.'("div",{className:'.$SV.'.'.$CSHORT.',children:['.join(",",@caps).']})', '" "';
    @caps=(); };
  for my $seg (split /(\[\[[^\]]*\]\])/, $s) {
    next unless length $seg;
    if ($seg =~ /^\[\[(.*)\]\]$/) { push @caps, $B.'("span",{className:'.$SV.'.'.$CKEY.',children:"'.$1.'"})'; }
    else { $flush->(); (my $t=$seg) =~ s/^\s+|\s+$//g; push @ch, '"'.$t.'"' if length $t; }
  }
  $flush->();
  push @objs, '{text:'.$E.'('.$FRAG.',{children:['.join(",",@ch).']})}';
}
my $new = '['.join(",",@objs).']';

# -- locate the tips array (balanced, string-aware) and splice --------------
my $opens=q~[{(~; my $closes=q~]})~; my $quotes=q~"'`~;
my @spans;
while ($c =~ /=>(\[\{text:)/g) {           # arrow returning [{text:…]  — helper name-agnostic
  my $start = pos($c) - length($1);
  my ($d, $end, $q) = (0, -1, "");
  for (my $k=$start; $k<length($c); $k++) {
    my $ch = substr($c,$k,1);
    if ($q ne "") { if ($ch eq "\\") { $k++; next } $q="" if $ch eq $q; next }  # inside string
    if (index($quotes,$ch)>=0) { $q=$ch; next }
    if    (index($opens,$ch)>=0)  { $d++ }
    elsif (index($closes,$ch)>=0) { $d--; if ($d==0) { $end=$k; last } }
  }
  push @spans, [$start, $end] if $end >= 0;
}
if (!@spans) { print "  – tips — array not found (already patched or structure changed)\n"; exit 0 }
substr($c, $_->[0], $_->[1]-$_->[0]+1) = $new for reverse @spans;  # splice back-to-front
open my $out,'>:raw',$target or die "$target: $!"; print $out $c;
printf "  ✓ tips (%d array%s, keycaps %s)\n", scalar(@spans), @spans>1?"s":"", $keycaps?"on":"off";
PERL

# 5) Rebrand the assistant name: bare "Claude" -> "Ruri" in display text.
#    Case-sensitive + identifier-boundary, so code identifiers (launchClaude,
#    openClaudeInTerminal…), lowercase model ids (claude-*), CSS vars
#    (--app-claude-*) and the CLAUDE.md filename are untouched. (?! Code) keeps
#    the "Claude Code" product name. Anchors of steps 1-4 contain no "Claude".
perl - "$TARGET_FILE" <<'PERL'
my ($t) = @ARGV;
my $c = do { open my $f,'<:raw',$t or die "$t: $!"; local $/; <$f> };
my $n = ($c =~ s/(?<![A-Za-z0-9_\$])Claude(?![A-Za-z0-9_\$(])(?! Code)/Ruri/g);
open my $o,'>:raw',$t or die "$t: $!"; print $o $c;
print $n ? "  ✓ rebrand Claude->Ruri ($n)\n" : "  – rebrand Claude->Ruri (none; already done or renamed)\n";
PERL

# CSS modifications for kawaii theming
if ! grep -q 'app-ruri-pink' "$CSS_FILE"; then
    sed -i -E \
        -e 's/(--app-claude-orange:#d97757;)/\1\n  --app-ruri-pink: #ff69b4;/' \
        -e 's/(--app-claude-clay-button-orange:#c6613f;)/\1\n  --app-ruri-clay-button-pink: #ec539c;/' \
        -e 's/--focus-ring-color:var\(--app-claude-orange\);/--focus-ring-color: var(--app-ruri-pink);/g' \
        -e 's/background-color:var\(--app-claude-clay-button-orange\);?/background-color: var(--app-ruri-clay-button-pink);/g' \
        -e 's/--focus-ring-color:var\(--app-primary-foreground\)/--focus-ring-color:var(--app-ruri-pink)/' \
        -e 's/background-color:var\(--app-primary-foreground\)/background-color:var(--app-ruri-clay-button-pink)/' \
        "$CSS_FILE"
fi

check "$CSS_FILE" '--app-ruri-pink' "CSS theming"

# 6) Ambient sparkles + cursor trail + corner ruri mascot (hops; hops fast
#    while generating). Self-contained overlay APPENDED to the webview — no
#    React coupling. "Generating" = a spinnerRow/loadingState element in the
#    DOM (CSS-module class prefix, hash-suffix-agnostic). Appended once each
#    (JS guarded by __ruriFx, CSS by the ruri-fx marker); survives updates.
perl - "$TARGET_FILE" "$CSS_FILE" "$NEW_SVG_FILE" <<'PERL'
my ($jsfile,$cssfile,$svgfile) = @ARGV;
my $svg = do { open my $f,'<:raw',$svgfile or die "$svgfile: $!"; local $/; <$f> };
$svg =~ s/<\?xml.*?\?>//s;                       # drop xml prolog
$svg =~ s/^\s+|\s+$//g;
$svg =~ s/\\/\\\\/g; $svg =~ s/"/\\"/g; $svg =~ s/\r?\n\s*/ /g;   # -> JS "…" string

my $js = <<'JS';

;(function(){if(window.__ruriFx)return;window.__ruriFx=1;
var SVG="__SVG__";
var reduce=window.matchMedia&&matchMedia("(prefers-reduced-motion: reduce)").matches;
function el(t,c){var e=document.createElement(t);if(c)e.className=c;return e;}
var amb=el("div","ruri-ambient"),g=["✨","🌸","💫","💜","🌟","🎀"],i;
for(i=0;i<18;i++){var s=document.createElement("span");s.textContent=g[i%g.length];s.style.left=(Math.random()*100)+"vw";s.style.animationDuration=(10+Math.random()*14)+"s";s.style.animationDelay=(-Math.random()*20)+"s";s.style.fontSize=(12+Math.random()*16)+"px";amb.appendChild(s);}
document.body.appendChild(amb);
var tg=["✨","💫","⭐","🌸"],last=0;
if(!reduce)document.addEventListener("mousemove",function(e){var n=Date.now();if(n-last<55)return;last=n;var t=el("div","ruri-trail");t.textContent=tg[Math.floor(Math.random()*tg.length)];t.style.left=e.clientX+"px";t.style.top=e.clientY+"px";document.body.appendChild(t);setTimeout(function(){t.remove();},800);});
var m=el("div","ruri-mascot"),b=el("div","ruri-mascot-body");b.innerHTML=SVG;m.appendChild(b);document.body.appendChild(m);
// generating = the spinnerRow has content (it is a persistent container; only filled while streaming)
var wasBusy=false;
function fxSettleDone(){b.classList.remove("settling");b.style.transition="";b.style.transform="";b.removeEventListener("transitionend",fxSettleDone);}
function fxBusy(on){if(on===wasBusy)return;wasBusy=on;
if(on){b.removeEventListener("transitionend",fxSettleDone);b.classList.remove("settling");b.style.transition="";b.style.transform="";m.classList.add("busy");
if(Date.now()-lastBurst>600){var sb=document.querySelector('[class*="sendButton"]');if(sb){var rb=sb.getBoundingClientRect();fxBurst(rb.left+rb.width/2,rb.top+rb.height/2);}}}
else{m.classList.remove("busy");
if(reduce){b.style.transition="";b.style.transform="";}
else{var tf=getComputedStyle(b).transform;b.classList.add("settling");b.style.transform=tf;b.style.transition="none";void b.offsetWidth;b.style.transition="transform .5s cubic-bezier(.34,1.56,.64,1)";b.style.transform="none";b.addEventListener("transitionend",fxSettleDone);}}}
setInterval(function(){var r=document.querySelector('[class*="spinnerRow"]');fxBusy(!!(r&&r.textContent.trim()));},200);
// heart/sparkle burst on send-button click (delegated: survives re-renders)
var burstG=["💖","✨","💕","🌟","💫","🎀"],lastBurst=0;
function fxBurst(x,y){if(reduce)return;lastBurst=Date.now();for(var i=0;i<12;i++){var p=el("div","ruri-burst");p.textContent=burstG[Math.floor(Math.random()*burstG.length)];p.style.left=x+"px";p.style.top=y+"px";document.body.appendChild(p);(function(p){var a=Math.random()*Math.PI*2,dist=40+Math.random()*70,dx=Math.cos(a)*dist,dy=Math.sin(a)*dist-30;requestAnimationFrame(function(){p.style.transform="translate(calc(-50% + "+dx+"px),calc(-50% + "+dy+"px)) scale(.4) rotate("+(Math.random()*180-90)+"deg)";p.style.opacity="0";});setTimeout(function(){p.remove();},950);})(p);}}
document.addEventListener("click",function(e){var t=e.target&&e.target.closest&&e.target.closest('[class*="sendButton"]');if(t){var r=t.getBoundingClientRect();fxBurst(r.left+r.width/2,r.top+r.height/2);}},true);
// rainbow comet around newly-appearing messages (skip the initial history flood)
var fxT0=Date.now(),fxNS="http://www.w3.org/2000/svg",fxPending=[],fxTimer=0;
(function(){var d=document.createElementNS(fxNS,"svg");d.style.cssText="position:absolute;width:0;height:0";d.innerHTML='<defs><linearGradient id="ruriGrad" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff2d55"/><stop offset=".2" stop-color="#ff9500"/><stop offset=".4" stop-color="#ffe600"/><stop offset=".6" stop-color="#34d857"/><stop offset=".8" stop-color="#00c2ff"/><stop offset="1" stop-color="#b14dff"/></linearGradient></defs>';document.body.appendChild(d);})();
function fxDraw(node){requestAnimationFrame(function(){var cs=getComputedStyle(node);if(cs.position==="static")node.style.position="relative";
var r=node.getBoundingClientRect(),w=r.width,h=r.height;if(w<8||h<8)return;
var sw=3.5,ins=sw/2,rad=Math.max(0,(parseFloat(cs.borderTopLeftRadius)||14)-ins);
var svg=document.createElementNS(fxNS,"svg");svg.setAttribute("class","ruri-rainbow");svg.setAttribute("viewBox","0 0 "+w+" "+h);svg.setAttribute("width",w);svg.setAttribute("height",h);
svg.innerHTML='<rect x="'+ins+'" y="'+ins+'" width="'+(w-sw)+'" height="'+(h-sw)+'" rx="'+rad+'" fill="none" stroke="url(#ruriGrad)" stroke-width="'+sw+'" stroke-linecap="round" pathLength="100" stroke-dasharray="32 68" class="ruri-rainbow-rect"/>';
node.appendChild(svg);setTimeout(function(){svg.remove();},700);});}
// debounce 120ms; >3 at once = bulk history load -> skip (marked seen so they never fire)
function fxFlush(){fxTimer=0;var q=fxPending;fxPending=[];if(q.length>3)return;for(var i=0;i<q.length;i++)fxDraw(q[i]);}
function fxRainbow(node){if(node.__ruriRb||reduce||Date.now()-fxT0<1200)return;node.__ruriRb=1;fxPending.push(node);if(fxTimer)clearTimeout(fxTimer);fxTimer=setTimeout(fxFlush,120);}
function fxScan(n){if(!n||n.nodeType!==1)return;if(n.matches&&n.matches('[class*="timelineMessage"]'))fxRainbow(n);if(n.querySelectorAll){var q=n.querySelectorAll('[class*="timelineMessage"]'),i;for(i=0;i<q.length;i++)fxRainbow(q[i]);}}
// observe ONLY the chat list, not document.body — otherwise every mousemove
// trail particle (appended to body) retriggers this, lagging mouse input.
var fxMO=new MutationObserver(function(ms){for(var i=0;i<ms.length;i++){var a=ms[i].addedNodes;for(var j=0;j<a.length;j++)fxScan(a[j]);}}),fxMOt=null;
function fxAttach(){var t=document.querySelector('[class*="messagesContainer"]');if(t&&t!==fxMOt){fxMOt=t;fxMO.disconnect();fxMO.observe(t,{childList:true,subtree:true});}}
fxAttach();setInterval(fxAttach,1000);
})();
JS
my @p = split /__SVG__/, $js; $js = $p[0].$svg.$p[1];    # splice svg without s/// interpolation

my $css = <<'CSS';

/* ruri-fx: ambient sparkles + cursor trail + corner mascot */
.ruri-ambient{position:fixed;inset:0;pointer-events:none;z-index:2147483000;overflow:hidden}
.ruri-ambient span{position:absolute;opacity:.5;animation:ruriDrift linear infinite;will-change:transform}
@keyframes ruriDrift{from{transform:translateY(110vh) rotate(0)}to{transform:translateY(-10vh) rotate(360deg)}}
.ruri-trail{position:fixed;pointer-events:none;z-index:2147483001;font-size:14px;animation:ruriTrail .8s ease-out forwards}
@keyframes ruriTrail{from{transform:translate(-50%,-50%) scale(1);opacity:.9}to{transform:translate(-50%,-140%) scale(.3);opacity:0}}
.ruri-mascot{position:fixed;right:18px;bottom:18px;z-index:2147483002;pointer-events:none;user-select:none}
.ruri-mascot-body{display:inline-block;animation:ruriHop 2.6s ease-in-out infinite;filter:drop-shadow(0 4px 10px rgba(236,83,156,.5))}
.ruri-mascot-body.settling{animation:none}
.ruri-mascot-body svg{width:54px;height:54px;display:block}
.ruri-mascot.busy .ruri-mascot-body{animation:ruriHopFast .55s ease-in-out infinite}
@keyframes ruriHop{0%,100%{transform:translateY(0) rotate(-2deg)}50%{transform:translateY(-5px) rotate(2deg)}}
@keyframes ruriHopFast{0%,100%{transform:translateY(0) rotate(-5deg)}50%{transform:translateY(-9px) rotate(5deg)}}
/* pastel scrollbar + selection — recolor the vscode slider vars (drives both
   monaco .slider divs and native scrollbar-color); !important beats inline */
:root{--vscode-scrollbarSlider-background:rgba(255,105,180,.5)!important;--vscode-scrollbarSlider-hoverBackground:rgba(255,105,180,.75)!important;--vscode-scrollbarSlider-activeBackground:rgba(236,83,156,.9)!important}
::selection{background:var(--app-ruri-pink,#ff69b4);color:#fff}
::-webkit-scrollbar-thumb{background:var(--app-ruri-pink,#ff69b4);border-radius:999px}
/* send-burst particles */
.ruri-burst{position:fixed;pointer-events:none;z-index:2147483001;font-size:16px;transform:translate(-50%,-50%) scale(1);opacity:.95;transition:transform .9s cubic-bezier(.22,.61,.36,1),opacity .9s ease-out;will-change:transform,opacity}
/* rainbow comet that travels once around a new Ruri message border.
   SVG stroke-dashoffset animates ALONG the path -> constant perimeter speed,
   aspect-ratio-independent (fixes conic-gradient bunching on long edges). */
.ruri-rainbow{position:absolute;left:0;top:0;pointer-events:none;z-index:5;overflow:visible;opacity:0;animation:ruriRbFade .62s ease-in-out forwards}
.ruri-rainbow-rect{animation:ruriDash .62s linear forwards;filter:drop-shadow(0 0 4px rgba(255,90,160,.75))}
@keyframes ruriDash{from{stroke-dashoffset:0}to{stroke-dashoffset:-100}}
@keyframes ruriRbFade{0%{opacity:0}10%{opacity:1}82%{opacity:1}100%{opacity:0}}
@media (prefers-reduced-motion:reduce){.ruri-ambient span,.ruri-mascot-body{animation:none!important}}
CSS

my $jc = do { open my $f,'<:raw',$jsfile or die "$jsfile: $!"; local $/; <$f> };
if ($jc !~ /__ruriFx/) { open my $o,'>>:raw',$jsfile or die $!; print $o $js; print "  ✓ ruri fx js\n"; }
else { print "  – ruri fx js (already present)\n"; }
my $cc = do { open my $f,'<:raw',$cssfile or die "$cssfile: $!"; local $/; <$f> };
if ($cc !~ /ruri-fx/) { open my $o,'>>:raw',$cssfile or die $!; print $o $css; print "  ✓ ruri fx css\n"; }
else { print "  – ruri fx css (already present)\n"; }
PERL

echo "UwU-fication complete. Review any ✗/– above."
