# Rows for pm: id state title owner deps due est prio, tab separated.
def lab(p): ([.labels[].name | select(startswith(p))] | first // "") | sub("^" + p; "");
def deps: [(.body // "") | split("\n")[] | select(test("^deps:")) | sub("^deps:[ \t]*"; "") | gsub("[# \r]"; "")] | (first // "");
.[] | [
  (.number | tostring),
  (if .state == "OPEN" then "open" else "done" end),
  (.title | gsub("[\t\n\r]"; " ")),
  (.assignees[0].login // ""),
  deps,
  (.milestone.dueOn // ""),
  lab("est:"),
  lab("prio:")
] | join("\t")
