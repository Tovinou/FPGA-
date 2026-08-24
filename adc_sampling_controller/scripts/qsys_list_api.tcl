package require -exact qsys 25.1
puts [lsort [info commands *instance*]]
puts [lsort [info commands *connection*]]
puts [lsort [info commands *interface*]]

