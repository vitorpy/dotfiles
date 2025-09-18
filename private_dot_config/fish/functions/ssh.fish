function ssh --wraps='TERM=xterm-256color /usr/bin/ssh' --description 'alias ssh=TERM=xterm-256color /usr/bin/ssh'
  TERM=xterm-256color /usr/bin/ssh $argv
        
end
