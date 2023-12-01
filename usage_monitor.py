#!/bin/env python

"""
Tracking of colabfold usage statistics based upon 
GridEngine accounting log
"""

from datetime import datetime
from subprocess import run
from time import mktime
import pandas as pd
import re

def parse_record(record):

	parsed=dict()
	req_fields=('jobnumber', 'hostname', 'owner', 'project', 'submit_cmd', 'qsub_time', 'exit_status', 
	     'failed', 'wallclock','maxrss','maxvmem')

	for line in record:
		fields = line.split()
		parsed[fields[0]]=' '.join(fields[1:])
	run_stats={k: parsed[k] for k in req_fields}

	return(run_stats)

def to_unix_time(time):
	"""
	Converts a UGE time format to a unix time format...

	Required parameters:
		time(str): UGE time representation

	Returns:
		unixtime(int): unix time representation
	"""

	datetime_obj = datetime.strptime(time, "%m/%d/%Y %H:%M:%S.%f")
	unixtime=mktime(datetime_obj.timetuple())

	return(unixtime)

def is_multimer(cmd):
	"""
	Determines whether a job is running a multimer prediction or not

	Required params:
		cmd(str): qsub command line

	Returns:
		multimer(bool): True if a multimer job, otherwise False
	"""

	if '_multimer_v' in cmd:
		return(True)
	else:
		return(False)

def to_bytes(usage):
	"""
	Converts a memory usage in M or G to bytes

	Required params:
		usage(str): memory usage string i.e. 19.888G
	
	Returns:
		bytes (int): Number of bytes
	"""
	suffix=usage[-1]

	# non Mb or Gb values will have an int as the suffix...
	if suffix=="M" or suffix=="G" or suffix=="T":
		usage=usage[:-1]

	if suffix=="M":
		bytes_usage=float(usage) * 1024 * 1024
	elif suffix=="G":
		bytes_usage=float(usage) * 1024 * 1024 * 1024
	elif suffix=="T":
		bytes_usage=float(usage) * 1024 * 1024 * 1024 * 1024
	else:
		bytes_usage=float(usage)

	return(int(bytes_usage))

def main():
	
	cmd=['qacct','-j','colabfold']
	result=run(cmd,capture_output=True,text=True,check=True)
	result=result.stdout.split("\n")

	all_stats=list()

	buf=list()
	for line in result:
		if (line=="==============================================================" \
		or line=="\n") and len(buf):
			run_stats=parse_record(buf)
			if len(run_stats.keys()):
				all_stats.append(run_stats)
		else:
			buf.append(line)

	all_stats=pd.DataFrame.from_dict(all_stats)
	all_stats['submit_time']=all_stats['qsub_time'].map(to_unix_time)
	all_stats['multimer_job']=all_stats['submit_cmd'].map(is_multimer)
	all_stats['maxrss_bytes']=all_stats['maxrss'].map(to_bytes)
	all_stats['maxvmem_bytes']=all_stats['maxvmem'].map(to_bytes)
	all_stats=all_stats.drop(['maxrss_bytes','maxvmem_bytes'],axis=1)
	all_stats.to_csv('colabfold_stats.txt',sep="\t",header=True, index_label='Count')

	total=len(all_stats)

if __name__ == '__main__':
	main()
