/// TRUE while the statcover browser control is shown -- gates the jitter
/// sound ping, because the control's JS keeps running (and pinging) even
/// while the window is hidden.
/client/var/statcover_visible = FALSE

/client/proc/show_stat_cover()
	src << browse_rsc(file('html/images/statcover.jpg'), "statcover.jpg")
	src << browse_rsc(file('html/images/statgrain.png'), "statgrain.png")
	// fcopy_rsc + REF(): winset image params can't resolve bare cache
	// filenames, only resource references -- same pattern as Label_Icon
	// (icons.dm:158-167).
	var/toplayer_rsc = fcopy_rsc(file("html/images/toplayer.png"))
	src << browse_rsc(toplayer_rsc, "toplayer.png")
	browse_queue_flush()
	var/uihtml = {"<html><head><style>
html,body{margin:0;padding:0;overflow:hidden;cursor:pointer;background:#000;}
img{width:100%;height:100%;display:block;object-fit:cover;opacity:1;transition:opacity 0.4s ease;}
#grain{position:absolute;top:0;left:0;width:100%;height:100%;background:url('statgrain.png');opacity:0;pointer-events:none;}
</style></head>
<body><img id='cover' src='statcover.jpg' onclick='fadeAndHide()'>
<div id='grain'></div>
<script>
function fadeAndHide() {
	document.getElementById('cover').style.opacity = '0';
	setTimeout(function() {
		window.location.href = 'byond://?src=[REF(src)];hide_stat_cover=1';
	}, 400);
}
// Occasional brief jitter -- pure JS margin nudges (BYOND browser controls
// run legacy-IE emulation, so CSS keyframes can't be relied on), on a
// randomized period so the art stutters every now and then, not constantly.
// Each burst also flashes crawling grain static over the art and pings
// BYOND once for the (visibility-gated) jitter sound.
function scheduleJitter() {
	setTimeout(function() {
		var c = document.getElementById('cover');
		var g = document.getElementById('grain');
		if (c) {
			// Ping the sound FIRST, then start the visuals after a short
			// lead -- the byond:// round trip + sound start lags the visual
			// burst otherwise (tunable lead below).
			window.location.href = 'byond://?src=[REF(src)];statcover_jitter=1';
			setTimeout(runJitterBurst, 250);
		}
		scheduleJitter();
	}, 6000 + Math.random() * 14000);
}
function runJitterBurst() {
	var c = document.getElementById('cover');
	var g = document.getElementById('grain');
	if (!c) { return; }
	var steps = 0;
	var t = setInterval(function() {
		c.style.marginLeft = (Math.floor(Math.random() * 5) - 2) + 'px';
		c.style.marginTop = (Math.floor(Math.random() * 5) - 2) + 'px';
		if (g) {
			g.style.opacity = (0.08 + Math.random() * 0.12).toFixed(2);
			g.style.backgroundPosition = Math.floor(Math.random() * 64) + 'px ' + Math.floor(Math.random() * 64) + 'px';
		}
		if (++steps > 5) {
			clearInterval(t);
			c.style.marginLeft = '0px';
			c.style.marginTop = '0px';
			if (g) { g.style.opacity = '0'; }
		}
	}, 40);
}
scheduleJitter();
</script></body></html>"}
	src << browse(uihtml, "window=statwindow.statcover")
	winset(src, "statwindow.statcover", "is-visible=true")
	// Cover the native Rules/Wiki/... buttons too: hide them and paint the
	// strip art as the infobuttons pane's own background. (They're skin
	// BUTTON elements in their own pane -- no HTML page can overlay them,
	// and an extra BROWSER element in their pane destabilized the buttons'
	// custom skin colors, rendering them gray.)
	for(var/btn in list("rules", "wiki", "forum", "github", "report-issue", "interface", "discord"))
		winset(src, "infobuttons.[btn]", "is-visible=false")
	// image-mode=center, not stretch: the pane is shorter than the art, and
	// BYOND's stretch resampling smears the art's blue/red glow pixels into
	// purple fringe along the edges. Centered 1:1 draws pixel-perfect and
	// crops the extremes instead.
	winset(src, "infobuttons", "image='[REF(toplayer_rsc)]';image-mode=center")
	// The splitter strip between the button row and the info panel shows the
	// child pane's navy through the seam between the two artworks -- tint it
	// black while covered so it reads as a bezel line, not a gap.
	winset(src, "info_and_buttons.info_button_child", "background-color=#000000")
	statcover_visible = TRUE

/client/proc/hide_stat_cover()
	winset(src, "statwindow.statcover", "is-visible=false")
	// Restore the button row at the moment the main cover's 400ms fade
	// completes (this proc is the post-fade href), reading as one uncover.
	winset(src, "infobuttons", "image=")
	for(var/btn in list("rules", "wiki", "forum", "github", "report-issue", "interface", "discord"))
		winset(src, "infobuttons.[btn]", "is-visible=true")
	winset(src, "info_and_buttons.info_button_child", "background-color=#0d1b33")
	statcover_visible = FALSE
