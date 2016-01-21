-- Public domain
local binfilename, varname = table.unpack(arg)
local bytes = assert(io.open(binfilename, "rb")):read("*a")
io.write("static char ",varname,"[] = \"")
for i = 1,#bytes do
  if i % 16 == 1 then io.write("\"\n\"") end
  io.write(string.format("\\x%02x", string.byte(bytes, i)))
end
io.write("\";\n")
