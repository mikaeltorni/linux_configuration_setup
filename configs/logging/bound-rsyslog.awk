# Preserve destinations and hooks, replacing only the retention directives.
/^[[:space:]]*(postrotate|prerotate|firstaction|lastaction)[[:space:]]*$/ { script = 1 }
script { print; if ($0 ~ /^[[:space:]]*endscript[[:space:]]*$/) script = 0; next }
/^[[:space:]]*(daily|weekly|monthly|yearly|hourly|compress|nocompress|delaycompress|nodelaycompress)[[:space:]]*(#.*)?$/ { next }
/^[[:space:]]*(rotate|maxsize|size|minsize)[[:space:]]+[^[:space:]]+[[:space:]]*(#.*)?$/ { next }
{ print }
/^[[:space:]]*\{[[:space:]]*$/ {
    print "    daily"
    print "    maxsize 100M"
    print "    rotate 7"
    print "    compress"
    print "    nodelaycompress"
}
