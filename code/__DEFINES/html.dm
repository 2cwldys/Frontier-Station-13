// Navy theme matching interface/skin.dmf's own palette (#0d1b33/#1a3560) --
// without this, every consumer of this macro (68+ files) renders on the
// browser's plain default white background instead.
#define HTML_SKELETON_INTERNAL(head, body) \
"<!DOCTYPE html><html><head><meta http-equiv='Content-Type' content='text/html; charset=UTF-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'><style>body{background-color:#0d1b33;color:#ffffff;font-family:Verdana,Geneva,sans-serif;}a,a:link,a:visited{color:#8ecdf7;}a:hover{color:#ffffff;background-color:#1a3560;}table,td,th{border-color:#1a3560;}input,select,textarea{background-color:#1a3560;color:#ffffff;border:1px solid #2a4a80;}hr{border-color:#1a3560;}</style>[head]</head><body>[body]</body></html>"

#define HTML_SKELETON_TITLE(title, body) HTML_SKELETON_INTERNAL("<title>[title]</title>", body)
#define HTML_SKELETON(body) HTML_SKELETON_INTERNAL("", body)
