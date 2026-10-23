# Print the php_value/php_flag/php_admin_* directives of .htaccess files that
# are active when PHP runs as php-fpm: everything except what sits inside an
# <IfModule php...> / <IfModule mod_php...> block (no PHP apache module is
# loaded with fpm; a negated <IfModule !php...> block stays active).
#   awk -f htaccess-active-php.awk FILE...
{ l = tolower($0); sub(/^[ \t]+/, "", l) }
FNR == 1 { d = 0 }
l ~ /^<ifmodule[ \t>]/ {
  m = l; sub(/^<ifmodule[ \t]+/, "", m); sub(/[ \t]*>.*$/, "", m)
  inert[++d] = (m ~ /^(mod_)?php[0-9]*(_module|\.c)?$/); next
}
l ~ /^<\/ifmodule/ { if (d > 0) d--; next }
l ~ /^php_(value|flag|admin_value|admin_flag)[ \t]/ {
  x = 0; for (i = 1; i <= d; i++) if (inert[i]) x = 1
  if (!x) print FILENAME ":" FNR ": " $0
}
