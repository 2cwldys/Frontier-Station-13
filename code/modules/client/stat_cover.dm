/client/proc/show_stat_cover()
	src << browse_rsc(file('html/images/statcover.jpg'), "statcover.jpg")
	browse_queue_flush()
	var/uihtml = {"<html><head><style>
html,body{margin:0;padding:0;overflow:hidden;cursor:pointer;background:#000;}
img{width:100%;height:100%;display:block;object-fit:cover;opacity:1;transition:opacity 0.4s ease;}
</style></head>
<body><img id='cover' src='statcover.jpg' onclick='fadeAndHide()'>
<script>
function fadeAndHide() {
	document.getElementById('cover').style.opacity = '0';
	setTimeout(function() {
		window.location.href = 'byond://?src=[REF(src)];hide_stat_cover=1';
	}, 400);
}
</script></body></html>"}
	src << browse(uihtml, "window=statwindow.statcover")
	winset(src, "statwindow.statcover", "is-visible=true")

/client/proc/hide_stat_cover()
	winset(src, "statwindow.statcover", "is-visible=false")
