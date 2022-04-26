from os import listdir, chdir
from os.path import isfile, join
import sys
import subprocess

# Define colors for printing
class colors:
	PASS = '\x1b[42m'
	FAIL = '\x1b[41m'
	BOLD = '\033[1m'
	RESET = '\033[0;0m'

keyword = ''
if ('--run_test' in sys.argv):
	keyword = sys.argv[sys.argv.index('--run_test')+1]

# Get list of existing workloads
path = './workloads/'
workloads = [f for f in listdir(path) if isfile(join(path, f))]
workloads = [f for f in workloads if keyword in f]
workloads.sort()
for i in range(len(workloads)):
	workloads[i] = workloads[i].split('.')[0]

# Parse baseline results
baseline_results = {}
baseline = open('../scripts/rtl_baseline', 'r')
for line in baseline:
	split_line = line.split(' ')
	baseline_results[split_line[0]] = float(split_line[1])

chdir('../compiler')
print(colors.BOLD + '{:<35}{:<4}    {:<5}    {:<6}'.format('WORKLOAD', 'TEST', 'TOPS', 'QoR') + colors.RESET)
for workload in workloads:
	subprocess.call(['cp', '../scripts/workloads/'+workload+'.py', './'], shell=False)
	sys.stdout.write('{:<35}'.format(workload))
	sys.stdout.flush()
	outfile = open('../scripts/reports/'+workload+'_rtl.rpt', 'w')
	subprocess.call(['python', workload+'.py', '-rtlsim'], stdout=outfile, shell=False)
	rptfile = open('../scripts/reports/'+workload+'_rtl.rpt', 'r')
	parse_rtl_res = False
	for line in rptfile:
		if (parse_rtl_res and ('Running simulation ... ' in line)):
			args = line.split()
			if('PASSED' in args[3]):
				print(colors.PASS + 'PASS' + colors.RESET, end='')
				result = args[10]
				if workload in baseline_results:
					comparison_to_baseline = ((float(args[10])/baseline_results[workload])-1) * 100
					if comparison_to_baseline >= 0:
						print ('    {:>5}    +{:<5.2f}'.format(result, comparison_to_baseline) + '%')
					else:
						print ('    {:>5}    {:<6.2f}'.format(result, comparison_to_baseline) + '%')
				else:
					print ('    {:>5}    N/A'.format(result))
			else:
				print(colors.FAIL + 'FAIL' + colors.RESET)
		elif 'Launching RTL Simulation' in line:
			parse_rtl_res = True
	if(not parse_rtl_res):
		print(colors.FAIL + 'FAIL' + colors.RESET)
	subprocess.call(['rm', workload+'.py'], shell=False)

