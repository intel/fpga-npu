length = 8192
with open('test_input.dat', 'w') as f:
	f.write(str(length)+" 40\n")
	for i in range(0, length):
		for j in range(0, 40):
			f.write(str((i % 256) - 128) + " ")
		f.write("\n")
