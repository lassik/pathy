-- Let me know if you want a copy under another permissive license.
-- lassi@lassi.io

function getopt(arg, justflags, argflags)
  local newarg, parsed = {}, {}
  local i = 1
  while i <= #arg do
    local ar = arg[i]
    i = i + 1
    if ar == "--" then
      break
    elseif string.sub(ar, 1, 2) == "--" then
      error("options starting with -- are not recognized")
    elseif string.sub(ar, 1, 1) == "-" and ar ~= "-" then
      for a = 2,string.len(ar) do
        local flag = string.sub(ar, a, a)
        if string.find(justflags, flag) then
          parsed[flag] = true
        elseif string.find(argflags, flag) then
          if i > #arg then error("option -"..flag.." needs an argument") end
          parsed[flag] = arg[i] -- If flag given more than once, last one wins
          i = i + 1
        else
          error("no such option: -"..flag)
        end
      end
    else
      table.insert(newarg, ar)
    end
  end
  for i = i,#arg do table.insert(newarg, arg[i]) end
  return newarg, parsed
end
