import sys
import os
try:
	import sqlite3
except:
	from pysqlite2 import dbapi2 as sqlite3


"""
This will run the making of the new database in PHLAWD

If the new database has enough additional sequences of
viridiplantae and the searchterm then it will trigger 
a phlawd update of the alignment

UPDATE: now this will read a config file db.update to determine the target and the searchterms
"""

dbconfigfile = "tempdb.config"
idfortarget = 33090 # NOTE id for plants

def count_searchterm_db(search,dbname):
	conn = sqlite3.connect(dbname)
	c = conn.cursor()
	c.execute("select left_value,right_value from taxonomy where ncbi_id=?", (idfortarget,))
	left = None
	right = None
	for j in c:
		left = int(j[0])
		right = int(j[1])
	c.close()
	count = 0
	c = conn.cursor()
	c.execute("select ncbi_id from sequence where description like '%"+search+"%';")
	for j in c:
		c2 = conn.cursor()
		c2.execute("select left_value,right_value from taxonomy where ncbi_id=?",(int(j[0]),))
		for k in c2:
			tl = int(k[0])
			tr = int(k[1])
			if tl > left and tr < right:
				count += 1
		c2.close()
	c.close()
	return count

def get_id_for_name(cladename,dbname):
	_id = None
	conn = sqlite3.connect(dbname)
	c = conn.cursor()
	c.execute("select ncbi_id from taxonomy where name=?", (cladename,))
	for j in c:
		_id = int(j[0])
	c.close()
	return _id

if __name__ == "__main__":
	if len(sys.argv) != 5:
		print "python autoupdate_phlawd_db.py phlawdlocation db.update newdbname olddbname"
		sys.exit(0)
	phlawd_prog = sys.argv[1] 
	newdbname = sys.argv[3]  #  temporary
	olddbname = sys.argv[4]  #  for example the existing rbcL.db 
	gbdivision = "pln"       #just hardcoding plant , NOTE this could be a parameter
	#update for reading file
	dbupdatefile = sys.argv[2] # for example db.update
	dbuf = open(dbupdatefile,"r")
	cladename = None
	searchterms = None
	for i in dbuf:
		spls = i.strip().split("=")
		if spls[0].strip().lower() == "clade":
			cladename = spls[1].strip()
		elif spls[0].strip().lower() == "search":
			searchterms = spls[1].split(",")
			for j in range(len(searchterms)):
				searchterms[j] = searchterms[j].strip()
	dbuf.close()
	print "searching on",searchterms
	idfortarget = get_id_for_name(cladename,olddbname)
	if idfortarget == None:
		print "the name",cladename,"was not found in the database"
		sys.exit(0)
	else:
		print "matched",idfortarget,"to",cladename

	"""
	need to write out the configuration file 
	"""
	configfile = open(dbconfigfile,"w")
	configfile.write("db = "+newdbname+"\n")
	configfile.write("division = "+gbdivision+"\n")
	configfile.write("download\n")
	configfile.close()

	"""
	run the phlawd command to make the database 
	"""
	cmd = phlawd_prog+" setupdb "+dbconfigfile
	print cmd
	os.system(cmd)    # takes around 1h 
	
	#update for multiple genes
	totalcount1 = 0
	totalcount2 = 0
	for i in range(len(searchterms)):
		"""
		read the old database and get the number of sequences 
		"""
		count1 = count_searchterm_db(searchterms[i],olddbname)
		"""
		read the database and determine how many new sequences there
		are in green plants given the search term
		"""
		count2 = count_searchterm_db(searchterms[i],newdbname)
		totalcount1 += count1
		totalcount2 += count2
		
	rebuild = False
	if (totalcount2 - totalcount1) > 100:  # NOTE this 100 could be a parameter
		rebuild = True
	if rebuild:
		print totalcount2-totalcount1,"new sequences that should be compared"	
		"""
		first mv the new database to the file of the old database
		"""
		cmd = "mv "+newdbname+" "+olddbname
		print cmd
		os.system(cmd)
		print "REBUILD REQUIRED"	
	else:
		print totalcount2-totalcount1,"new sequences, not enough"
		cmd = "rm "+newdbname
		print cmd
		os.system(cmd)
		print "NO_REBUILD"	

