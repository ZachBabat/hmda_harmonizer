/*
TITLE: hmda_harmonizer.do
AUTHOR: Zach Babat, 4/18/22

STRUCTURE: 
			0. Set-up, unzipping:
			1. Merging together HMDA panels, 2010-2017 (call this "pre-2017")
			2. Resolving "problembanks" - cases where RSSD == 0, RSSD ==., or
			   cases where RSSD is nonunique in a given year
				2.1 - Resolving duplicate nonmissing RSSDs
				2.2 - Resolving missing RSSDs 
			3. Merging on post-2017 data (2018-2021)
			4. Resolving "donuts" and "switchers"
				4.1 - Identifying RSSD switchers using HMDA IDs 
				4.2 - Identifying "donuts"		
				4.3 - Matching donuts onto information from the Avery file 
				4.4 - Using information from the Avery file to identify RSSD switchers
			5. Final adjustments: adding lenders in loan data but not panels, quality checks
*/

/*0. SET-UP*/
clear all 
set more off
set varabbrev off 
cap log close	

*USER: CHANGE "ROOT" MACRO TO THE LOCATION OF THE HMDA_HARMONIZER FOLDER
global ROOT "C:/Users/zbabat/Desktop/hmda_harmonizer"
cd "${ROOT}"
log using "hmda_harmonizer.log", append

*USER: SEE "Sources.docx" FOR INSTRUCTIONS TO DOWNLOAD RAW INPUT FILES (est. time 5-15 mins)

*UNZIPPING DOWNLOADS AND CONVERTING TO DTA WHEN NEEDED
*HMDA Lender Panels:
/*2010-2017 panel data*/
forvalues i = 2010/2017 {
	unzipfile hmda_lender_panels/hmda_`i'_panel
	clear
	import delimited hmda_`i'_panel, varnames(1)
	save hmda_lender_panels/hmda_`i'_panel, replace
	erase hmda_`i'_panel.csv
}

/*Fixing an error in 2012 HMDA reporter panel:
all the RSSD identifiers have the number "0" appended to the end - we fix that
here by taking every digit from the RSSD identifiers except the last one, and
save the corrected file. Note that 79 observations have respondentrssdid = 0, these
just get converted to missing, which is fine since 0 isn't a valid RSSD*/

use hmda_lender_panels/hmda_2012_panel
tostring respondentrssdid, gen(stringid)
replace stringid = substr(stringid, 1, strlen(stringid) - 1)
drop respondentrssdid 
destring stringid, replace 
ren stringid respondentrssdid 
save hmda_lender_panels/hmda_2012_panel, replace 

/*2018-2021 panel data*/
forvalues i = 2018/2021 {
	unzipfile hmda_lender_panels/`i'_public_panel_csv
	clear
	import delimited `i'_public_panel_csv, varnames(1)
	save hmda_lender_panels/`i'_public_panel_csv, replace
	erase `i'_public_panel_csv.csv
	
	*cleaning up junk files included with the 2018 data
	if `i' == 2018 {
		erase __MACOSX/._`i'_public_panel_csv.csv
		rmdir __MACOSX
	}
}

/*Avery File data*/
cd avery_file
unzipfile hmdpanel17, replace 
unzipfile HMDA_lender_files_2018-2021, replace 
cd ..

/*NIC data*/
cd nic 
unzipfile CSV_ATTRIBUTES_ACTIVE, replace 
unzipfile CSV_ATTRIBUTES_CLOSED, replace 
unzipfile CSV_ATTRIBUTES_BRANCHES, replace 
unzipfile CSV_RELATIONSHIPS, replace 
unzipfile CSV_TRANSFORMATIONS, replace 
cd ..

/*HMDA-to-LEI crosswalk panel*/
cd hmda_to_lei_xwalk
unzipfile arid2017_to_lei_xref_csv, replace 
clear 
import delimited arid2017_to_lei_xref_csv.csv, varnames(1)
save arid2017_to_lei_xref_csv, replace 
erase arid2017_to_lei_xref_csv.csv
cd ..


	
/*SECTION 1. MERGING TOGETHER HMDA PANELS, PRE-2017****************************/
use "hmda_lender_panels/hmda_2010_panel"
keep respondentrssdid respondentid agencycode respondentnamepanel parentrssdid 
ren respondentid respondentid2010
ren agencycode agencycode2010
replace respondentnamepanel = strtrim(respondentnamepanel)
ren respondentnamepanel respondentnamepanel2010
ren parentrssdid parentrssdid2010

/*Identifying "problembanks", which are banks in a given year missing RSSD codes
or with duplicate RSSD codes. We dump these into a separate file to be handled
later, and then proceed with merging together the banks without these issues using
RSSD codes*/
preserve 

	*tagging bank as problem bank if RSSD = 0 or it's missing RSSD
	gen problembank = 0
	replace problembank = 1 if respondentrssdid == 0 | respondentrssdid == .
	
	*tagging bank as problem bank if its RSSD is duplicated within the same year
	duplicates tag respondentrssdid, gen(dup)
	replace problembank = 1 if dup > 0
	keep if problembank == 1
	replace dup = . if respondentrssdid == 0 | respondentrssdid == . //we don't care about number of duplicates for RSSD = 0/missing RSSD
	
	*the problembanks file will be in long format - we want consistently 
	*populated variables for year, name, and HMDA ID (detailed below)
	gen year = 2010
	gen name = respondentnamepanel2010
	tostring agencycode2010, replace 
	gen concatid = agencycode2010 + respondentid2010 
	
	tempfile problembanks
	save `problembanks', replace 

restore 

drop if respondentrssdid == 0

*dropping duplicates also handles dropping banks missing RSSD 
duplicates tag respondentrssdid, gen(dup)
drop if dup > 0
drop dup 

*in a given year - HMDA lenders are identified by the unique concatenation of 
*respondentid and agencycode. Call this "concatid"
tostring agencycode2010, replace 
gen concatid2010 = agencycode2010 + respondentid2010

tempfile working 
save `working'
clear 

/*Now, we loop through the procedure above for each panel file, and merge
together using respondentrssdid*/
forvalues x = 2011/2017 {
	use "hmda_lender_panels/hmda_`x'_panel"
	keep respondentrssdid respondentid agencycode respondentnamepanel parentrssdid 
	ren respondentid respondentid`x'
	ren agencycode agencycode`x'
	replace respondentnamepanel = strtrim(respondentnamepanel)
	ren respondentnamepanel respondentnamepanel`x'
	ren parentrssdid parentrssdid`x'
	
	preserve 
	
		gen problembank = 0
		replace problembank = 1 if respondentrssdid == 0 | respondentrssdid == .
		
		duplicates tag respondentrssdid, gen(dup)
		replace problembank = 1 if dup > 0
		keep if problembank == 1
		replace dup = . if respondentrssdid == 0 | respondentrssdid == .  
		
		gen year = `x'
		gen name = respondentnamepanel`x'
		
		tostring agencycode`x', replace
		gen concatid = agencycode`x' + respondentid`x'
		
		append using `problembanks'
		save `problembanks', replace 
		
	restore
	
	drop if respondentrssdid == 0
	
	duplicates tag respondentrssdid, gen(dup)
	drop if dup > 0
	drop dup 
	
	/*Generating concatid - see note in the 2010 processing*/
	tostring agencycode`x', replace
	gen concatid`x' = agencycode`x' + respondentid`x'
	
	merge 1:1 respondentrssdid using `working', gen(merge`x')
	save `working', replace
	clear
}

use `working'
order respondentname* concatid*, sequential 
order respondentrssdid respondentname*

save "hmda_harmonizer_panel", replace

/*SECTION 2. Resolving "problembanks" cases where RSSD == 0, RSSD ==., or
cases where RSSD is nonunique in a given year**********************************/

/*We now have a dataset containing the HMDA IDs of our problem banks.
Visual inspection indicates that the HMDA IDs for these banks seem pretty stable.
We'll do the following:
	-Reshape problem banks to long format
	-Reshape the main dataset of non-problem banks (003_hmda_id_panel) to long
	 format
	-Append problembanks onto the non-problem bank, and sort by concatid to try
	 matching banks missing RSSD info to their non-problem bank counterparts
	-For the problembanks that match to non-problem banks, merge the concatids 
	 back into the main dataset using the update option
	 
The result of this is that we'll be matching problembanks, with missing RSSD info,
to the identifier time series to which they belong*/

use `problembanks', clear
keep year name dup problembank concatid respondentrssdid

/*SECTION 2.1 - Setting aside banks with duplicate non-missing RSSDs***********/
*Ultimately, these get merged into the main dataset much later, but it's helpful
*to separate these from the missing-RSSD problembanks and set them aside to be
*merged later

preserve 

	keep if dup != .

*2.a.i 
*Duplicate RSSDs where one concatid is listed under the wrong RSSD

	*providing the correct RSSD for "LEGACY CDC  LLC" (distinct from LEGACY BK) 
	replace respondentrssdid = 3343717 if concatid == "373-0149048"

	*providing the correct RSSD for "MORTGAGE SOLUTIONS  LLC" (distinct from VANTAGE CU)
	replace respondentrssdid = 4320395 if concatid == "543-1847878"

	*providing the correct RSSD for "BANK OF ASH GROVE" (distinct from OLD MO BK)
	replace respondentrssdid = 568443 if concatid == "30000008252"

*2.a.ii
*Duplicate RSSDs where both concatids truly correspond to the same RSSD
	
*In short, these include:
*FIRST NB OF WELLINGTON and IMPACT BANK
*PATHFINDER CMRL BK and PATHFINDER BK
*CNB B&T and CORNERSTONE BANK & TRUST NA
*FIRST T&SB and FIRST T&SB

	*Now, we reshape wide before merging back onto the main dataset.
	*First, we need to change one of the bank's names so observations are uniquely
	*identified in each year - we'll change it back after the reshape
	replace name = "FIRST TSB" if concatid == "30000008092"
	drop problembank dup
	reshape wide concatid, i(respondentrssdid name) j(year)
	replace name = "FIRST T&SB" if name == "FIRST TSB"
	*populating wide-form name variables - note none of these banks report in year 2017
	forvalues x = 2010/2016 {
		gen respondentnamepanel`x' = ""
		replace respondentnamepanel`x' = name if concatid`x' != ""
	}
	drop name
	tempfile dupbanks
	save `dupbanks'
	
restore 


/*SECTION 2.2 - Sorting out banks with missing RSSDs***************************/ 

*first, we drop the duplicate-RSSD problembanks, which we just handled above
drop if dup != .
*next, it's helpful to have a missing RSSD be represented with 0, not .
replace respondentrssdid = 0 if respondentrssdid == .
save `problembanks', replace 

/*
*confirming that HMDA IDs are stable for these banks - let's check that there's 
*a 1-to-1 correspondence between concatid and bank name
order concatid year name
bysort concatid: egen namecount = nvals(name) 
*we get that 87 observations have more than 1 name corresponding to a concatid.
*If you sort by namecount concatid year, we can see that most of these are due
*to changes like adding punctuation in the name. A few others are actual name 
*changes, but if you look them up, they appear to be the same institution just renaming.

by name: egen idcount = nvals(concatid)
*We get that each name matches to just one concatid 

*!!!note to ask Sophie how she wants to handle, e.g., Hunt Finance/Centerline acquisition - see Slack note
sort namecount concatid year 
*/

*now, we need a long-form version of our main panel
clear 
use "hmda_harmonizer_panel"
keep respondentnamepanel* concatid* respondentrssdid 
reshape long respondentnamepanel@ concatid@, i(respondentrssdid) j(year)
drop if concatid == ""
gen problembank = 0

*dataset should have 56713 observations after this
append using `problembanks' 

/*FIRST - MERGING PROBLEMBANKS THAT MATCH NON-PROBLEMBANKS INTO THE MAIN ID PANEL
USING CONCATIDS*/

*first, we only want to be working with the institutions that have at least
*1 problembank observation, but aren't all problembanks
bysort concatid (year): gen totalyears = _N
by concatid: egen problembankcontributions = total(problembank)
keep if problembankcontributions > 0 & (problembankcontributions != totalyears)

order respondentrssdid year name respondentnamepanel concatid problembank

*now, we have problembanks matched up with counterparts from our main panel,
*which have RSSD IDs. But because we've matched these up using the concatid,
*let's check that each concatid corresponds to only one non-zero (i.e. valid) RSSD

by concatid: egen rssdcount = nvals(respondentrssdid)
sort rssdcount concatid year

*we get two cases where a concatid matches to more than one valid RSSD - we'll
*generate RSSDs for all the problembanks first, then manually provide the correct
*RSSDs for these anomalous cases after.

*because problembanks all have RSSD == 0, and all their counterparts from the main 
*panel have non-zero RSSDs, we do the following:

bysort concatid: egen rssdkey = max(respondentrssdid)

*2.b.ii.5
*Recoding cases where concatid matches to more than one non-missing RSSD 

*Note - this next line is not a recoding! In 2016, concatid 732-0293417 is assigned to RSSD 3842368.
*It's just that it gets tagged with a different value in the rssdkey variable that 
*we're using to match problembanks up to their true RSSDs, and we're correcting that 
*error here. So there's no recoding.
replace rssdkey = 3842368 if concatid == "732-0293417" & year == 2016

*This one is a recoding - see documentation
replace rssdkey = 3075401 if concatid == "774-1110065"

*preparing to reshape wide so we can merge back onto the main panel.
*first, it will be helpful later to have a dataset of the banks we're merging on in this step:
preserve 

	keep year concatid 
	tempfile problems_round1
	save `problems_round1'
	
restore

replace respondentrssdid = rssdkey
drop respondentrssdid problembank dup totalyears problembankcontributions rssdcount 
ren rssdkey respondentrssdid
replace respondentnamepanel = name if respondentnamepanel == ""
drop name
reshape wide respondentnamepanel concatid, i(respondentrssdid) j(year)
order respondentrssdid concatid* respondentname*


*setting aside a bank that creates an issue in the merge
preserve

	*RSSDID = 3881992, Allen Tate Mortgage Services/Allen Tate Mortgage Partners
	*in the original HMDA panel files, this bank was listed with
	*concatid == 77291100002 from 2010-2016, and concatid == 747-5133238 in 2017. These
	*ids all merged together in 003_hmda_id_panel already. But, there is another observation
	*with concatid == 747-5133238 in year 2016, without an RSSD attached. This flags as 
	*a problembank, and when we merge it on, it results in a _merge == 5 observation.
	*I think it is correct to keep both concatids and assign them to the same RSSD for 2016.
	*This means Allen Tate is another duplicate RSSD bank - it will be easier to 
	*merge it onto the main panel with the rest of the RSSD duplicates in the tempfile `dupbanks' 
	keep if respondentrssdid == 3881992
	
	*we'll want this to only be a single row containing this single-year extra
	*concatid for Allen Tate, identified with the correct RSSD. So we set the 
	*information for 2017 to missing - Allen Tate loans will be picked up by the "main"
	*concatid in that year
	replace concatid2017 = ""
	replace respondentnamepanel2017 = ""
	
	tempfile allentate
	save `allentate', replace 
	
restore 

drop if respondentrssdid == 3881992 | respondentrssdid == 3874118

*we want to do a merge with the "update" option using the main panel as the 
*master so we can correctly observe where the problembanks update the main panel
tempfile problempanel1 
save `problempanel1'
use "hmda_harmonizer_panel", clear
merge 1:1 respondentrssdid using `problempanel1', update gen(update1)

*2.b.ii.8
*Recode HMDA ID in 2010 for two banks with an identical name that I believe are assigned the wrong HMDA IDs

replace concatid2010 = "77552800000" if respondentrssdid == 3874118
replace respondentnamepanel2010 = "WALL STREET MORTGAGE BANKERS" if respondentrssdid == 3874118
replace agencycode2010 = "7" if respondentrssdid == 3874118
replace respondentid2010 = "7552800000" if respondentrssdid == 3874118

replace concatid2010 = "766-0674421" if respondentrssdid == 4327965
replace respondentnamepanel2010 = "WALL STREET MORTGAGE BANKERS" if respondentrssdid == 4327965
replace agencycode2010 = "7" if respondentrssdid == 4327965
replace respondentid2010 = "766-0674421" if respondentrssdid == 4327965

save "hmda_harmonizer_panel.dta", replace 

/*SECOND - MERGING PROBLEMBANKS THAT DON'T MATCH NON-PROBLEMBANKS INTO THE MAIN ID PANEL
USING THE AVERY FILE*/

*here, we attempt to find RSSD info from the Avery file 

use `problembanks', clear
merge 1:1 concatid year using `problems_round1', keep(master) nogen


preserve 

	keep if year == 2010
			gen hmprid = substr(concatid, 2, .)
			gen code = substr(concatid, 1, 1)
			destring code, replace 
			local y = 10
			merge 1:1 hmprid code using "avery_file/hmdpanel17.dta", keep(match)
			keep hmprid code name year RSSD`y'
			
			tempfile test
			save `test', replace

restore 


forvalues x = 2011/2017 {
	preserve 
	
		keep if year == `x'
		gen hmprid = substr(concatid, 2, .)
		gen code = substr(concatid, 1, 1)
		destring code, replace 
		local y = `x' - 2000
		merge 1:1 hmprid code using "avery_file/hmdpanel17.dta", keep(match)
		keep hmprid code name year RSSD`y'
		append using `test'
		save `test', replace

	restore 
}

use `test', clear

*collapsing to one observation per bank
tostring code, replace
gen concatid = code + hmprid
collapse (min) RSSD*, by(concatid)

*There are two duplicated RSSD codes in 2010.
*After auditing, it seems correct that RSSD 4320256 corresponds to SEFCU.
*RSSD 3703898 matches to two concatids, but neither of them seem a plausible match
*for this RSSD code, so we set RSSD to missing for both of these banks.
*Note that this is not recoding HMDA lender panel data, but rather correcting the 
*results of the merge with the Avery file
replace RSSD10 = . if concatid == "72022500009"
replace RSSD10 = . if RSSD10 == 3703898

*reshaping long 
reshape long RSSD@, i(concatid) j(year)
replace year = year + 2000

*reshaping wide again so we're in terms of unique RSSDs
ren RSSD rssd
drop if rssd == 0 | rssd == .

*we want a record of the concatid-years that we match in this step
preserve
	keep concatid year
	tempfile problems_round2
	save `problems_round2', replace 
restore 

reshape wide concatid, i(rssd) j(year)
 
*it's helpful to have the names for these banks so I can make sure the merge 
*method is valid. 

preserve 

	keep rssd 
	tempfile namematched
	save `namematched'
	
restore

preserve 

	keep rssd concatid2010 
	keep if concatid2010 != ""
	gen agencycode = substr(concatid2010, 1, 1)
	destring agencycode, replace 
	gen respondentid = substr(concatid2010, 2, .)
	count
	merge 1:1 respondentid agencycode using "hmda_lender_panels/hmda_2010_panel.dta", keep(match)
	
	
	keep rssd concatid2010 respondentnamepanel
	replace respondentnamepanel = strtrim(respondentnamepanel)
	ren respondentnamepanel respondentnamepanel2010 
	merge 1:1 rssd using `namematched', assert(using match) nogen
	save `namematched', replace 

restore

*note - don't seem to be any banks in this subset for year 2015
foreach x in 2011 2012 2013 2014 2016 2017 {
	preserve 
	
	keep rssd concatid`x' 
	keep if concatid`x' != ""
	gen agencycode = substr(concatid`x', 1, 1)
	destring agencycode, replace 
	gen respondentid = substr(concatid`x', 2, .)
	count
	merge 1:1 respondentid agencycode using "hmda_lender_panels/hmda_`x'_panel.dta", keep(match)
	
	
	keep rssd concatid`x' respondentnamepanel
	replace respondentnamepanel = strtrim(respondentnamepanel)
	ren respondentnamepanel respondentnamepanel`x'
	merge 1:1 rssd using `namematched', assert(using match) nogen
	save `namematched', replace 

	restore 
} 

use `namematched', clear

*2.c.iii.1
replace rssd = 102379 if concatid2010 == "599-0000324"
ren rssd respondentrssdid 
save `namematched', replace 

*now, once again merging these onto the main panel using the update option.
*note that we do m:1 merges now that we have some multi-concatid RSSDs
use "hmda_harmonizer_panel", clear
merge m:1 respondentrssdid using `namematched', update gen(update2)

*FLAG FOR FUTURE!!! the bank with RSSD 4160667 is super complicated,
*check that we actually want it all in one row like this. Note also
*this is one of the banks we update in the merge immediately above

drop update1 update2
save "hmda_harmonizer_panel", replace 

/*THIRD - MERGE THE PROBLEMBANKS THAT DIDN'T FIND NON-PROBLEMBANK MATCHES INTO THE ID PANEL*/
*at this point, we give up - if a bank hasn't been associated with an RSSD yet,
*we assume that information is not in HMDA. There do seem to be some banks that
*legitimately don't have an RSSD, which makes sense in light of the fact that
*RSSDs do not get assigned to every financial institution

*reloading our initial set of problembank observations and dropping the ones
*we've matched in the steps above
use `problembanks', clear

merge 1:1 concatid year using `problems_round1', keep(master) nogen
merge 1:1 concatid year using `problems_round2', keep(master) nogen

*reshaping wide - we drop rssd because rssd = 0 for all these banks
*PROVIDE MORE DOCUMENTATION ON GENERATING THE FAKE RSSDs here
drop respondentrssdid problembank dup

/*Code to confirm that each concatid here corresponds to only one bank, and cases
where concatid corresponds to more than one bank are either cosmetic (e.g. difference
in punctuation of name across years) or the same bank changing names
by concatid: egen namecount = nvals(name)
sort namecount concatid year
*/

gen rown = _n
bysort concatid: egen idnum = max(rown)
tostring idnum, replace
by concatid: gen metaid = "A" + idnum
drop rown idnum
reshape wide name concatid, i(metaid) j(year)
order concatid* name*, sequential
order metaid
ren name* respondentnamepanel*

*appending, not merging, onto the main panel - we don't merge because, assuming
*that these banks truly have no RSSD IDs, these are entirely new rows that are
*unrepresented among the banks already included in the main panel 
append using "hmda_harmonizer_panel"
order respondentnamepanel* concatid*, sequential
order respondentrssdid metaid
save "hmda_harmonizer_panel", replace 

*now, we have banks identified using RSSDs and banks identified using metaids in 
*the same panel. This is a problem if we want to merge on other banks, because
*those ID variables can be missing. Let's create a "masterid" variable that can
*hold either the RSSD or the metaid - now we have a never-missing variable we can
*use in merges
tostring respondentrssdid, gen(masterid)
replace masterid = metaid if metaid != ""
order masterid
save "hmda_harmonizer_panel", replace 


/*SECTION 2.3 - Merging on banks with duplicate non-missing RSSDs**************/
use `dupbanks', clear
order concatid* respondentname*, sequential
order respondentrssdid 

*generating masterid values for this data so we can merge using masterid, which
*won't be empty for any bank
tostring respondentrssdid, gen(masterid)
save `dupbanks', replace 

use "hmda_harmonizer_panel", clear
merge 1:m masterid using `dupbanks', update nogen

*we need to make some adjustments - the merge we just did successfully merges on
*the cases where an RSSD matches to multiple concatids in a given year. But,
*for the rows that correspond to the "extra" concatids that deviate from a bank's
*main concatid series, those rows also get all the "standard" concatids that come
*in the years before. This seems like it could get messy - maybe we could accidentally
*double the number of loans that go to a bank because loans match onto a given 
*concatid twice. Let's clean this up so that one-off "extra" concatid rows don't 
*have the "standard" concatids in the years before

*IMPACT BANK - RSSD 369453, CONCATID 20000369453 IN 2012
foreach x in 2010 2011 2013 2014 2015 2016 {
	replace concatid`x' = "" if concatid2012 == "20000369453"
	replace respondentnamepanel`x' = "" if concatid2012 == "20000369453"
	replace respondentid`x' = "" if concatid2012 == "20000369453"
	replace agencycode`x' = "" if concatid2012 == "20000369453"
	replace parentrssdid`x' = . if concatid2012 == "20000369453"
}
forvalues x = 2011/2017 {
	replace merge`x' = . if concatid2012 == "20000369453"
}

*PATHFINDER CMRL BK - RSSD 729310, CONCATID 30000057497 IN 2016
foreach x in 2010 2011 2012 2013 2014 2015 2017 {
	replace concatid`x' = "" if concatid2016 == "30000057497"
	replace respondentnamepanel`x' = "" if concatid2016 == "30000057497"
	replace respondentid`x' = "" if concatid2016 == "30000057497"
	replace agencycode`x' = "" if concatid2016 == "30000057497"
	replace parentrssdid`x' = . if concatid2016 == "30000057497"
}
forvalues x = 2011/2017{
	replace merge`x' = . if concatid2016 == "30000057497"
}

*CORNERSTONE BANK & TRUST  NA - RSSD 764647, CONCATID 199-0014347 IN 2011
foreach x in 2010 {
	replace concatid`x' = "" if concatid2011 == "199-0014347"
	replace respondentnamepanel`x' = "" if concatid2011 == "199-0014347"
	replace respondentid`x' = "" if concatid2011 == "199-0014347"
	replace agencycode`x' = "" if concatid2011 == "199-0014347"
	replace parentrssdid`x' = . if concatid2011 == "199-0014347"
}
forvalues x = 2011/2017{
	replace merge`x' = . if concatid2011 == "199-0014347"
}

*FIRST T&SB - RSSD 831044, CONCATID 199-0025111 IN 2015
foreach x in 2010 2011 2012 2013 2014 {
	replace concatid`x' = "" if concatid2015 == "199-0025111"
	replace respondentnamepanel`x' = "" if concatid2015 == "199-0025111"
	replace respondentid`x' = "" if concatid2015 == "199-0025111"
	replace agencycode`x' = "" if concatid2015 == "199-0025111"
	replace parentrssdid`x' = . if concatid2015 == "199-0025111"
}
forvalues x = 2011/2017{
	replace merge`x' = . if concatid2015 == "199-0025111"
}

*appending on the bank we set aside in section 2.2
append using `allentate'
replace masterid = "3881992" if concatid2016 == "747-5133238"

save "hmda_harmonizer_panel", replace 

/*SECTION 3. MERGING ON POST-2017 DATA*****************************************/
*SUBSECTION 1
*Using LEI as a merge key, merge together banks in the 2018-2021 data
*Set aside 20 banks with more than 1 RSSD per LEI

*SUBSECTION 2
*Looking at the LEIs that don't come with RSSDs, try to recover RSSDs from the NIC dataset
*Perform an update merge to add recovered RSSDs to the main 2018-2021 panel
*Repeat, using the Avery file instead of the NIC dataset

*SUBSECTION 3
*For the banks still missing RSSDs, take three measures to try to match up to pre-2017 banks
*	Use concatids, as found in the individual year HMDA lender panels
*	Use the LEI-concatid crosswalk from HMDA
*	Look up LEIs in the Avery files to look again for concatids or RSSD 
*After this, we give up and assume we found all the RSSDs that can be found

*SUBSECTION 4
*Generate unique IDs for banks that lack RSSD or metaid
*Collapse 6 pairs of duplicate-RSSD observations into one bank per pair
*Match the 2018-2021 panel back onto the pre-2017 panel using RSSD/metaid

*SUBSECTION 5 
*Merging on multi-RSSD LEIs from subsection 1

/*SUBSECTION 1: MERGING 2018-2021 PANELS, SETTING ASIDE MULTI-RSSD BANKS*/

*First, we'll merge the 2018-2021 panels together using LEI as a merge key
*Rather than actually merging, we'll append these panels together, set aside
*the lenders that have more than 1 RSSD per LEI, then reshape wide using LEI as the unique identifier.
*This is equivalent to a merge on LEI but it lets us identify the multi-RSSD LEIs 
use "hmda_lender_panels/2018_public_panel_csv", clear
keep lei respondent_rssd respondent_name activity_year 
ren activity_year year 
ren respondent_rssd rssd 
ren respondent_name name 
tempfile long2018 
save `long2018'

forvalues i = 2019/2021 {
	use "hmda_lender_panels/`i'_public_panel_csv", clear
	keep lei respondent_rssd respondent_name activity_year 
	ren activity_year year 
	ren respondent_rssd rssd 
	ren respondent_name name 
	append using `long2018'
	save `long2018', replace 
}

*identifying cases where there is more than 1 RSSD corresponding to an LEI - there are 20 such LEIS
bysort lei (year): egen rssdcount = nvals(rssd)

*setting aside the 20 multi-RSSD LEIs
preserve 

	keep if rssdcount > 1
	tempfile multi_RSSD_leis
	save `multi_RSSD_leis'

restore 

*now, dropping those multi-RSSD LEI observations and reshaping wide, so we have our 
*basic panel for post-2017 banks 
drop if rssdcount > 1
drop rssdcount 
reshape wide rssd name, i(lei) j(year)

*by construction, every LEI in this panel corresponds to 1 RSSD
*but we can't arbitrarily pick one rssd[year] variable to be the RSSD for the entire row,
*since some banks aren't populated in all years

*so we just create an rssd variable, and replace it with the value of the earliest non-missing RSSD code,
*which is fine since they're all the same conditional on being non-missing

gen rssd = .
replace rssd = rssd2018 
replace rssd = rssd2019 if rssd == .
replace rssd = rssd2020 if rssd == .
replace rssd = rssd2021 if rssd == .
assert rssd != .
drop rssd2018 rssd2019 rssd2020 rssd2021
order rssd

tempfile workingpost2017
save `workingpost2017', replace 

keep if rssd == -1
tempfile missingrssdpost2017
save `missingrssdpost2017', replace

/*SUBSECTION 2: TRYING TO ADD RSSDs TO BANKS MISSING THEM*/

*Right now, we have 503 observations (out of 6025) that have rssd == -1.
*First, we'll try using the NIC datasets to match from each of these 503 banks
*LEI's to their RSSDs.
*To the best of my knowledge, banks are listed in one of the three NIC "Attributes" datasets - 
*we'll append these all together and then attempt merging on all the rssd == -1 banks

*NOTE - I NEED TO TYPE OUT A BETTER EXPLANATION, BUT I THINK "BRANCHES" WON'T 
*ACTUALLY CONTAIN ANY BANKS, I THINK IT'S LITERALLY JUST BRANCH OFFICES.
*NOTE THAT NONE OF THE "BRANCHES" BANKS HAVE AN LEI

clear
import delimited "nic/CSV_ATTRIBUTES_ACTIVE.CSV"
tempfile active
keep id_rssd id_lei nm_lgl
gen active = 1
save `active', replace
clear 

import delimited "nic/CSV_ATTRIBUTES_CLOSED.CSV"
tempfile closed
keep id_rssd id_lei nm_lgl
gen active = 0
save `closed', replace

append using `active'

*we have thousands of obs with LEI == 0 (mostly really old banks), and 6 observations
*with non-zero duplicate LEIs, but these turn out not to matter for this merge.
*All the banks that were missing RSSDs that we are able to match have unique non-zero LEIs
ren id_lei lei
merge m:1 lei using `missingrssdpost2017' 

keep if _merge == 3
keep lei id_rssd
ren id_rssd rssd

*now, we update our working panel with the RSSDs we just linked to these LEI codes
tempfile update1
save `update1', replace 

clear
use `workingpost2017'
merge 1:1 lei using `update1', update replace nogen
save `workingpost2017', replace 

*Let's reload the list of missing RSSD banks, drop the banks that just matched 
*to RSSDs in the NIC dataset, and keep working 

clear 
use `missingrssdpost2017'
merge 1:1 lei using `update1', keep(master) nogen
save `missingrssdpost2017', replace

*We have 486 banks still missing RSSDs. We'll now turn to the 2018 and 2019 Avery 
*files to try to fill the gaps. Note that as of 6/27/22, I do not see the publication
*of a 2020 or 2021 Avery file, so banks that are only in HMDA in 2020 and 2021 won't
*be matched in the Avery files

*First, we merge together the Avery files using LEI, so we have the names and RSSDs for every bank
use LEI RSSD18 NAME18 using "avery_file/hmda_panel_2018", clear
merge 1:1 LEI using "avery_file/hmda_panel_2019", nogen keepusing (LEI RSSD19 NAME19)
ren LEI lei 

*now we merge on the banks to which we're trying to add RSSDs 
merge 1:1 lei using `missingrssdpost2017'
*filter to banks that matched and have a non-zero, non-missing RSSD in either 2018 or 2019
keep if ((RSSD18 != 0 & RSSD18 != .) | (RSSD19 != 0 & RSSD19 != .)) & _merge == 3
*assert that RSSDs match if populated for both years
assert RSSD18==RSSD19 if (RSSD18 != 0 & RSSD18 != .) & (RSSD19 != 0 & RSSD19 != .)

*Arbitrarily, fill in with 2018 if 2018 is populated, and 2019 if not
replace rssd = RSSD18 if (RSSD18 != 0 & RSSD18 != .)
replace rssd = RSSD19 if rssd == -1

*now, we update our working panel with the RSSDs we just linked to these LEI codes
keep rssd lei
tempfile update2
save `update2', replace 

clear
use `workingpost2017'
merge 1:1 lei using `update2', update replace nogen
save `workingpost2017', replace 

*Let's reload the list of missing RSSD banks, drop the banks that just matched 
*to RSSDs in the Avery file, and keep working 
clear 
use `missingrssdpost2017'
merge 1:1 lei using `update2', keep(master) nogen

save `missingrssdpost2017', replace

*We are down to 473 banks still missing RSSDs.

/*SUBSECTION 3: MATCHING MISSING RSSD BANKS TO PRE-2017 BANKS BY PRE-2017 HMDA ID*/
*After the steps above, we assume that post-2017 banks truly have no RSSD attached.
*We now do one last check that the post-2017 banks don't have any pre-2017
*counterparts using HMDA IDs, which we look for using:
	*The 2018-2020 HMDA bank panels
	*The lei-to-HMDA ID crosswalk, created by HMDA (we demonstrate this step is not necessary)
	*The Avery file

*First, let's take our working panel, and merge it on to the HMDA panels in each
*year to recover what each panel says is the HMDA ID

forvalues i = 2018/2019 {
	merge 1:1 lei using "hmda_lender_panels/`i'_public_panel_csv", ///
	keepusing(arid_2017) gen(merge`i') keep(master match)
	ren arid_2017 arid_`i'
}

forvalues i = 2020/2021 {
	merge 1:1 lei using "hmda_lender_panels/`i'_public_panel_csv", ///
	keepusing(id_2017 agency_code) gen(merge`i') keep(master match)
	ren id_2017 arid_`i'
	ren agency_code agency_code_`i'
}

*As it turns out, of the banks that match onto a valid HMDA ID, they all match
*to a valid HDMA ID in 2018. I believe all the valid HMDA IDs for a given bank
*agree across years, but for simplicity of coding and because 2018 was the first
*year after HMDA started using LEIs as the key for the panel, we'll just keep
*the 2018 HMDA IDs.

*Note that we only care about the 2018 IDs because we are just trying to link
*these rows up to their pre-2017 IDs. We don't need to worry about donuts around
*the year 2017 as long as every one of the banks that finds *some* kind of 
*HMDA ID merges onto the pre-2017 panel using the 2018 ID. Once we establish
*the pre-2017 and post-2017 link, we don't need to worry about what the post-2017
*panels list as HMDA ID, because we use LEI as the ID in the loan-level data in post-2017 years

/*3.d.ii.1
The following block of code demonstrates that, conditional on matching to a valid HMDA ID,
a bank matches to a valid HMDA ID in 2018.
count if merge2018 == 3 & arid_2018 != "-1" & arid_2018 != ""
forvalues i = 2019/2021{
	di `i'
	count if merge`i' == 3 & arid_`i' != "-1" & arid_`i' != ""
	count if (merge2018 == 3 & arid_2018 != "-1" & arid_2018 != "") & (merge`i' == 3 & arid_`i' != "-1" & arid_`i' != "")
}


*In addition, we show here that of the banks that did not match to a valid
*HMDA ID in the merge we just executed, all of those non-matches also do not find
*a match in the  lei-to-arid crosswalk put out by HMDA. So we don't need to look 
*for HMDA IDs in that file


preserve 
	
	*keep only banks that found no valid HMDA ID in the merges above
	drop if (arid_2018 != "-1" & arid_2018 != "") | (arid_2019 != "-1" & arid_2019 != "") | ///
	(arid_2020 != "-1" & arid_2020 != "") | (arid_2021 != "-1" & arid_2021 != "")

	tempfile xwalktest
	save `xwalktest'
	clear 

	import delimited "hmda_to_lei_xwalk/arid2017_to_lei_xref_csv.csv", varnames(1)
	ren lei_2018 lei
	merge 1:1 lei using `xwalktest'
	assert _merge != 3

restore
*/

keep if (arid_2018 != "-1" & arid_2018 != "") | (arid_2019 != "-1" & arid_2019 != "") | ///
(arid_2020 != "-1" & arid_2020 != "") | (arid_2021 != "-1" & arid_2021 != "")

assert (arid_2018 != "-1" & arid_2018 != "")

keep rssd lei name* arid_2018

*We now have 124 post-2017 banks that don't have RSSD codes, but that do have
*pre-2017 HMDA IDs filled out in the lender panels. We want to match these
*post-2017 banks to their pre-2017 counterparts, and we do this here

tempfile aridmerge1
save `aridmerge1'
clear

use "hmda_harmonizer_panel" 
*we need to make a variable that has the 2017 HMDA IDs reformatted to match
*the post-2017 IDs. Namely, we need to remove "-" characters

gen arid_2018 = subinstr(concatid2017, "-", "", .)

*3.d.iii.1 - 3.d.iii.3
*we're about to merge the 124 missing RSSD banks we identified with HMDA IDs above
*onto the panel of bank IDs, with arid_2018 as the merge key. This works almost
*perfectly, but 12 banks don't match. Of those 12, 6 should match but don't because
*they either 1) report in 2016, but not 2017, or 2) have HMDA IDs formatted slightly
*differently than in our panel above (one version features a "-" or a leading zero in 
*the respondentid.) 

*Below I manually code the arid_2018 variable to make sure the pre-2017
*banks find their post-2017 counterparts. You can verify that these recodings are 
*correct because the names for these concatids match in the pre- and post-2017 lender panels.

*Note that this is not a recoding of the actual ID codes used to match banks to loans 
*in the pre-2017 data. This is just to improve the veracity of matching post-2017 banks 
*onto their pre-2017 counterparts using pre-2017 HMDA ID as a merge key
replace arid_2018 = "7261234319" if masterid == "A50" //corrected from 726-1234319, reports only in 2016
replace arid_2018 = "7300217804" if masterid == "A7" //corrected from 70300217804
replace arid_2018 = "761341084" if masterid == "A9" //corrected from 706-1341084
replace arid_2018 = "7753197409" if masterid == "A198" //corrected from 775-3197409, reports only in 2016
replace arid_2018 = "781-1250682" if masterid == "A209" //corrected from 781-1250682
replace arid_2018 = "962-1627636" if masterid == "A241" //corrected from 962-1627636

*For the other 6 post-2017 banks that don't match, I was unable to find banks in the pre-2017
*data that look like suitable matches, so we are unable to connect the post-2017 banks
*despite them having populated HMDA ID variables in the lender panels

drop if arid_2018 == ""
order arid_2018
merge 1:1 arid_2018 using `aridmerge1'

sort _merge arid_2018 
order _merge arid_2018

*keeping only primary identifying information and merging back onto post-2017 panel
keep if _merge == 3
keep respondentrssdid metaid lei
ren respondentrssdid rssd 
save `aridmerge1', replace

clear
use `workingpost2017'
merge 1:1 lei using `aridmerge1', update replace nogen
sort rssd metaid
order metaid, after(rssd)
save `workingpost2017', replace 
*Note that the merge above is the first time the "metaid" variable gets introduced
*into the post-2017 panel. This makes sense, since we had only been merging on 
*RSSD before, and metaid is reserved for banks that don't have RSSDs.


/*3.d.ii.2
Below is code showing that the remaining missing RSSD banks don't find 
*HMDA IDs in the Avery file, and therefore we don't need to merge on any info from
*the Avery file to help connect post-2017 banks to pre-2017 counterparts

*Let's reload the list of missing RSSD banks, drop the banks that just matched 
*to HMDA IDs in the pre-2017 data, and keep working 
clear 
use `missingrssdpost2017'
merge 1:1 lei using `aridmerge1', keep(master) nogen
save `missingrssdpost2017', replace

merge 1:1 lei using "avery_file/hmda_panel_2018", ///
	keepusing(oldid CODE17 hmprid) keep(master match) gen(avery1)

ren hmprid hmprid18	
ren CODE17 code18 
	
merge 1:1 lei using "avery_file/hmda_panel_2019", ///
	keepusing(CODE17 hmprid) keep(master match) gen(avery2)

ren hmprid hmprid19
ren CODE17 code19

*The oldid, hmprid*, and code* variables are all empty, except for 6 banks. These
*6 banks are the same 6 banks discussed around line 972 above. Even though the
*HMDA lender panels give pre-2017 HMDA IDs for these, they don't merge onto
*the pre-2017 panel and I could not find any suitable matches in the pre-2017 panel
*when I checked manually. 
*/

*We now have only 355 banks missing RSSD IDs or other information that could match
*post-2017 banks onto pre-2017 banks.

*At this point, we conclude that banks missing RSSDs and pre-2017 HMDA IDs do not
*appear in the pre-2017 panel. We now stop trying to match these banks onto other
*ID codes and move on to finalizing the post-2017 panel and merging it onto the
*pre-2017 panel.


/*SUBSECTION 4 - CLEAN-UP, MERGING ONTO PRE-2017 PANEL*/
*Generating the masterid variable. For each bank, this will be the first variable
*from the following list that is not missing:
	*rssd
	*metaid
	*lei (if masterid = lei, then a bank only shows up in the post-2017 data, and
	*it has no pre-2017 counterpart)

tostring rssd, gen(masterid)
replace masterid = metaid if metaid != ""
replace masterid = lei if masterid == "-1"

*It will be helpful to have variables that hold the LEI for each bank in each year.

*In the post-2017 data, loans are not matched to banks with HMDA IDs, but rather
*with LEI codes. Here, we generate "concatid2018-2021" variables to match the format
*of the pre-2017 panel. (It's helpful to have distinct columns for LEI in each year,
*because this handles the extremely rare case of lei code changes for a given bank)

gen concatid2018 = lei if name2018 != ""
gen concatid2019 = lei if name2019 != ""
gen concatid2020 = lei if name2020 != ""
gen concatid2021 = lei if name2021 != ""

*3.e.ii.1
*For 6 banks, we end up with duplicate RSSD observations. 4 of them appear to 
*clearly the same bank, since they share a name and RSSD, and the LEI's appear 
*identical except for probable typos (replacing a 1 with an I, or a 0 with an O). 
*Here, we merge the duplicates into one row. Later, we will populate each year 
*with whichever version of the LEI that appears in that year - regardless of 
*whether the LEI has a typo in one year or another, we just want to make sure that
*this RSSD can match onto the observations for each bank in each year

replace name2019 = "Friend Bank" if name2018 == "Friend Bank"
drop if name2019 == "Friend Bank" & name2018 == ""

replace name2018 = "Great Nations Bank" if name2019 == "Great Nations Bank"
drop if name2018 == "Great Nations Bank" & name2019 == ""

replace name2019 = "Holy Rosary Regional Credit Union" if name2018 == "Holy Rosary Regional Credit Union"
drop if name2019 == "Holy Rosary Regional Credit Union" & name2018 == ""

replace name2018 = "INROADS FEDERAL CREDIT UNION" if name2019 == "INROADS"
drop if name2018 == "INROADS FEDERAL CREDIT UNION" & name2019 == ""

*populating the "typo" versions of the LEIs for the 4 banks immediately above:
replace concatid2019 = "54930033V1OQ5VFHI630" if rssd == 244037
replace concatid2019 = "5493000JBDASE0SXC167" if rssd == 522696
replace concatid2018 = "5493002Q15QUDX4RGW52" if rssd == 701370
replace concatid2018 = "254900TGSOSDEDP36K37" if rssd == 3599804

*3.e.ii.2
*Now we resolve the last two banks that had duplicate RSSD observations
replace name2021 = "Citizens State Bank" if lei == "549300TQL7MVZ6OPN578"
replace concatid2021 = "549300B3BEP9WW99IR76" if lei == "549300TQL7MVZ6OPN578" 
drop if lei == "549300B3BEP9WW99IR76"

replace name2021 = "First Missouri State Bank of Cape County" if lei == "549300EHOXTFKJXVWZ10"
replace concatid2021 = "5493005C8ZBTKUWJPI93" if lei == "549300EHOXTFKJXVWZ10"
drop if lei == "5493005C8ZBTKUWJPI93"

*Dropping the lei variable, since we have at least two cases where LEI switches
drop lei

*Now, we merge these post-2017 banks onto the pre-2017 banks.
isid masterid
ren rssd respondentrssdid
replace respondentrssdid = . if respondentrssdid == -1
save `workingpost2017', replace 

*We do the merge as an update/replace merge to ensure that there are no conflicting
*values in the data when matching on masterid 
use "hmda_harmonizer_panel", clear 
merge m:1 masterid using `workingpost2017', gen(prepostmerge) update replace
assert prepostmerge != 4 & prepostmerge != 5

*Cleaning up the dataset
ren respondentrssdid rssd 
ren respondentnamepanel* name*

order masterid rssd metaid prepostmerge 
order concatid* name*, after(prepostmerge) sequential
order agencycode2010 respondentid2010 agencycode2011 respondentid2011 ///
agencycode2012 respondentid2012 agencycode2013 respondentid2013 agencycode2014 respondentid2014 ///
agencycode2015 respondentid2015 agencycode2016 respondentid2016 agencycode2017 respondentid2017 /// 
merge2*, after(name2021)
order parent*, after(merge2017) sequential

*Because we merged m:1 using masterid, two pre-2017 rows with duplicate RSSDs 
*both match to unique rows in the post-2017 data. Fixing here:
replace concatid2018 = "" if concatid2016 == "747-5133238"
replace concatid2019 = "" if concatid2016 == "747-5133238"
replace concatid2020 = "" if concatid2016 == "747-5133238"
replace concatid2021 = "" if concatid2016 == "747-5133238"

replace concatid2018 = "" if concatid2016 == "30000057497"
replace concatid2019 = "" if concatid2016 == "30000057497"
replace concatid2020 = "" if concatid2016 == "30000057497"
replace concatid2021 = "" if concatid2016 == "30000057497"

save "hmda_harmonizer_panel", replace

*3.f

/*SUBSECTION 5: MERGING ON MULTI-RSSD LEIs FROM SUBSECTION 1*/
*Dealing with the multi-RSSD LEI observations from subsection 1:
use `multi_RSSD_leis', clear

*In a few cases, the RSSDs associated with an LEI just switch to missing/-1 - we
*can fill those in with the non-missing RSSD for that LEI 
replace rssd = 508270 if lei == "254900U6H520K7TCA169" //Glen Burnie
replace rssd = 326344 if lei == "5493006IBJS6XC0DFJ29" //The Peoples State Bank of Newton, Illinois
replace rssd = 511579 if lei == "5493006MA7WP1WL8U431" //Kern Schools FCU, confirmed this RSSD only changed names using NIC website
replace rssd = 3944664 if lei == "549300BRJZYHYKT4BJ84" //Home Point Financial Corporation

*LEI 54930048P8RWCQHQM310 changes names from WEI Mortgage LLC to ARC HOME LLC - 
*looking at the WEI Mortgage website, it says "WEI Mortgage is a trade name for Arc Home LLC".
*These two are the same bank.
replace rssd = 3883080 if lei == "54930048P8RWCQHQM310"

drop rssdcount

reshape wide lei name, i(rssd) j(year)


*THIS IS OUR FIRST TIME EXPLICITLY RECODING SWITCHER BANKS INTO ONE. HOW WILL WE DO THIS?
*WE'LL KEEP TWO ROWS, ONE FOR EACH RSSD. BUT, WE TAG BOTH ROWS WITH THE MASTERID 
*CORRESPONDING TO THE EARLIEST RSSD CODE, AND MERGE USING MASTERID.
*MY PRIOR IS GENERALLY THAT TWO BANKS WITH THE SAME LEI ARE INDEED THE SAME INSTITUTION -
*I'M USUALLY LOOKING TO SEE IF THERE'S ANY REASON TO THINK OTHERWISE.

*In a few cases where the RSSD associated with an LEI switches from a holding 
*company to a held bank, or vice versa, I'll usually group these. Since the HMDA
*identifiers are what's most important for filers, I'll assume that a shared LEI 
*between these two entities means they're effectively the same lender.  

gen masterid = ""

*generating an "LEI" variable that's constant across years so it's easier to 
*code the masterid variable
gen lei = lei2018
replace lei = lei2019 if lei==""
replace lei = lei2020 if lei==""
replace lei = lei2021 if lei==""
order masterid lei
sort lei

*Populating masterid with the RSSDs assigned above
replace masterid = "508270" if lei == "254900U6H520K7TCA169" 
replace masterid = "326344" if lei == "5493006IBJS6XC0DFJ29"
replace masterid = "511579" if lei == "5493006MA7WP1WL8U431"
replace masterid = "3944664" if lei == "549300BRJZYHYKT4BJ84"
replace masterid = "3883080" if lei == "54930048P8RWCQHQM310"

*Regent Financial Group, Inc. - there is no record of an RSSD transformation in 
*the NIC dataset, but these two banks share an LEI and an address. (The names actually
*might differ - 5213908 is actually listed as "Recent Financial Group, Inc." in NIC)
replace masterid = "5019678" if lei == "254900LW5BPW0G1LMW49"

*Draper and Kramer Mortgage Corp. - this bank is listed in the NIC data as 
*1st Advantage Mortgage, but there's a page on the Draper and Kramer website 
*showing that 1st Advantage changed its name to Draper and Kramer. We can also see this
*in the time series of names for RSSD 3876710. Though I cannot find evidence of an
*RSSD change to 3327511 (and 3327511 does not show up in the NIC dataset), because 
*these two RSSDs are associated by LEI and name, it's probably fair to group them
*together.
replace masterid = "3876710" if lei == "5493001R92DY5DI1DI85"

*There is no evidence for an RSSD change here, but this appears to me like some 
*form of typo or deletion - the RSSD changes from 980951 to 98095, and there is 
*no record of RSSD 98095 in the NIC dataset
replace masterid = "980951" if lei == "5493003QF1L7XNSWRM19"

*Community First Credit Union - despite having the same LEI, I believe we should
*keep these two banks separate. In the NIC dataset, RSSD 649397 is marked with 
*"charter discontinued," consistent with the bank being bought out by another meaningfully
*different group, as opposed to "charter retained." This looks more like an acquisition 
*after which the bank might change characteristics, as opposed to a simple name or RSSD change.
replace masterid = "649397" if rssd == 649397
replace masterid = "64897" if rssd == 64897

*NorthMarq Capital Finance, L.L.C - both of these RSSDs dropped out of the NIC dataset 
*in 2009, so we don't have any data from that. But we'll assume these two are
*the same institution based on name and LEI
replace masterid = "3310456" if lei == "549300AV8QD552DSI743"

*Cooperativa de Ahorro y Credito de Aguada - the RSSD changes between 2019 and 2020.
*There's no record of this in the NIC data, but these two banks share a name and LEI.
*Based on the pre-2017 data, I think this bank actually switches between these two
*RSSDs between 2016 and 2017. We'll use the first of these RSSDs to appear, 3878750,
*as the masterid
replace masterid = "3878750" if lei == "549300BGJTHEIKSJJS77"

*SIS Bancorp, MHC - According to NIC, RSSD 3815054 is the parent company of 
*RSSD 111205. 111205 reports from 2010-2017 under "Sanford Inst For Svg" (presumably
*becomes "SIS" later), and again from 2019-2020, so let's group these two banks together under that RSSD
replace masterid = "111205" if lei == "549300DK2AEMKCO4JZ92"

*Homeland Bancshares, Inc. - According to NIC, 3816547 is a holding company for 
*251978. Because these share a name and LEI, let's group them together.
replace masterid = "251978" if lei == "549300DOQN3O7NL3CA31"

*First United Corporation - another holding company/held lender relationship.
replace masterid = "61122" if lei == "549300G54QPXQLB4KN58"

*Banc of California, National Association - another holding company/held lender 
*relationship. It appears that the RSSDs switch back and forth in the pre-2017 data, 
*but begin with 200378, so we'll make that the masterid
replace masterid = "200378" if lei == "549300IBHVRZNE4YFN80"

*Village Bank and Trust Financial Corp. - another holding company/held lender 
*relationship. It appears that the RSSDs switch back and forth in the pre-2017 data, 
*but begin with 2760232, so we'll make that the masterid
replace masterid = "2760232" if lei == "549300NIJITDSZ8M7H32"

*National Bankshares, Inc. - another holding company/held lender 
*relationship.
replace masterid = "754929" if lei == "549300Q745S62Q6QNW78"

*Residential Mortgage, LLC - another holding company/held lender 
*relationship. It appears that the RSSDs switch back and forth in the pre-2017 data, 
*but begin with 200378, so we'll make that the masterid
replace masterid = "3195242" if lei == "549300SCFWZXMDMZPE93"

*F&M Bank Corp. - another holding company/held lender relationship.
replace masterid = "713926" if lei == "549300V2YLC1I721HE07"

*Union State Bank of Fargo - this one is complicated. I think RSSD 968557 was 
*Union State Bank of Fargo. In 2021, USB Fargo was acquired by RSSD 977951, which 
*was called Border State Bank. Upon acquiring USB Fargo, Border State Bank 
*assumed the name of its acquisition and became USB Fargo. However, based on the NIC dataset, 
*the charter for USB Fargo was discontinued, so these two RSSD codes should be considered
*distinct lenders
replace masterid = "968557" if rssd == 968557
replace masterid = "977951" if rssd == 977951

drop lei
ren lei* concatid* 
save `multi_RSSD_leis', replace 

*after the work we just did, a few rows in the main panel should be linked with the same masterid.
use "hmda_harmonizer_panel", clear 

replace masterid = "200378" if rssd == 3153130
replace masterid = "2760232" if rssd == 3251027
replace masterid = "3195242" if rssd == 4802136
replace masterid = "3878750" if rssd == 4253439

*I cannot figure out where, but I have found a row that we tried to switch to another 
*RSSD up above. We still ended up with two rows corresponding to a given concatid, 
*which is wrong in this case.
drop if masterid == "5026434" //duplicate row for Capital Farm Credit

merge m:1 rssd using `multi_RSSD_leis', update gen(multi_rssd_lei_merge)
assert multi_rssd_lei_merge == 1 | multi_rssd_lei_merge == 2 | multi_rssd_lei_merge == 4
drop multi_rssd_lei_merge
sort masterid

save "hmda_harmonizer_panel", replace
*we have now completed merging together all the pre-2017 and post-2017 rows

/*SECTION 4. RSSD SWITCHERS AND HMDA ID DONUTS*****************************/
/*There are two cases that we need to catch:
	*1. "Switchers" -
	*These are cases when an institution changes its RSSD over our observed
	*timeframe. In such cases, we'll need to link the distinct RSSDs with the 
	*same masterid 

	*2. "Donuts" - 
	*These are cases when a bank is present in HMDA in one year, not present
	*in a later year, then is present again in a year after that. This is not
	*inherently a problem, but it might suggest the bank is reporting under a different
	*RSSD in that year

*Sometimes, a donut occurs because a bank truly is not represented in HMDA in a 
*given year. Other times, it occurs when a bank temporarily files under a different
*RSSD (I am struggling to figure out why this happens, but we have good reason to believe
*it does occur - see the rows corresponding to Capital One (masterid 112837)
*/

/*SUBSECTION 1: USE NIC DATASET TO LOOK FOR BANKS THAT SWITCH RSSDs*/
use "hmda_harmonizer_panel", clear 
keep masterid concatid* name* 
duplicates tag masterid, gen(flag)
drop if flag > 0
reshape long concatid@ name@, i(masterid) j(year)

drop if concatid == ""

*Grouping by HMDA ID, we'll count how many RSSDs are associated with each bank over time.
*We'll keep only banks with HMDA IDs that get mapped onto by more than one RSSD - because these are single HMDA IDs 
*associated with more than one RSSD, these are potential "RSSD-switcher" banks 

bysort concatid: egen idcount = nvals(masterid)
keep if idcount > 1
sort concatid year

*4.a.v-4.a.vi
*I want to merge this onto the NIC transformations dataset to see if there are 
*any RSSD switches that we can confirm are an RSSD switch in which the predecessor 
*and successor RSSDs are economically distinct. For this exercise, RSSD transformations 
*with trnsfm_cd == 1 ("Charter Discontinued") will be considered transformations 
*in which the original lender no longer persists

destring masterid, gen(id_rssd_predecessor)
order id_rssd_predecessor
tempfile longformconcatcheck 
save `longformconcatcheck'
clear 

import delimited "nic/CSV_TRANSFORMATIONS.CSV"
tostring dt_trans, gen(year)
replace year = substr(year, 1, 4)
destring year, replace 
keep if year >= 2009 //in case a transformation occurs in 2009 but doesn't take effect until 2010

*some transformations split one predecessor RSSD into multiple successor RSSDs - let's
*drop these from our purview. It won't actually affect the results, since we'll still 
*be checking concatids that don't match onto this dataset, this will only increase 
*the amount of manual work we have to do

duplicates tag id_rssd_predecessor, gen(flag)
drop if flag > 0

merge 1:m id_rssd_predecessor using `longformconcatcheck'

drop if _merge == 1

*applying a trnsfm_cd code to all obs within a concatid 
bysort concatid (year): egen code = min(trnsfm_cd)
order code
drop if code == 1 //Charter Discontinued - in these cases, we consider predecessor and successor distinct 

*at this point, the ones that are left didn't match to the NIC dataset, so we check manually 
assert _merge == 2 
keep masterid concatid year name 
order masterid concatid year name

/*At this point, I am looking at the data and making decisions.

*If one concatid changes RSSDs, it might indicate those two RSSDs are linked. 
*I am going to be conservative in linking two RSSDs together - in particular, I am
*looking for one of the following:
	*Information from the NIC indicating that one RSSD transforms into another 
	*Information from the NIC indicating that two banks are linked (e.g. with a common holding company)
	*Some other strong information suggesting that the two banks are linked (e.g. all info is the same except a 
	*probable typo)
	
*My notes on this judgement process are contained in Appendix B of the documentation 
*file, under "HMDA Crosswalk Documentation"
*/

*Now, implementing the changes described above: 
use "hmda_harmonizer_panel", clear

*Credit Suisse Lending LLC
replace masterid = "4455073" if masterid == "445073"
*Northwest Consumer Discount Co 
replace masterid = "2351078" if masterid == "4727529"
*Envoy Mortgage Ltd
replace masterid = "3844492" if masterid == "4379151"
*FM Lending Services Inc.
replace masterid = "3882560" if masterid == "4741561"
*Agstar Financial Services ACA
replace masterid = "3950469" if masterid == "3636110"
*Southwest Stage Funding 
replace masterid = "3876390" if masterid == "3875390"
*Cooperative de Ahorro y Credit 
replace masterid = "2383060" if masterid == "4537317"
*360 Mortgage Solutions LLC 
replace masterid = "3715220" if masterid == "4185736"
*Entrust Mortgage LLC 
replace masterid = "3720532" if masterid == "4185688"

save "hmda_harmonizer_panel", replace 

/*SUBSECTION 2: IDENTIFYING DONUTS*/
*First, we identify the donuts
use "hmda_harmonizer_panel", clear

preserve 

	*we have to drop duplicate masterid rows or we can't reshape later.
	*almost none of these are donuts, and of those that are donuts, all but 
	*one are donuts we've already "filled" by matching to another masterid
	duplicates tag masterid, gen(dup)
	drop if dup > 0

	forvalues x = 2010/2021 {
		gen pop`x' = 0
		replace pop`x' = 1 if concatid`x' != ""
	}

	keep masterid concat* pop*
	reshape long concatid@ pop@, i(masterid) j(year)

	by masterid: egen minyear = min(year) if pop == 1
	by masterid: egen maxyear = max(year) if pop == 1
	by masterid: egen foo = min(minyear)
	by masterid: egen bar = max(maxyear)
	replace minyear = foo
	replace maxyear = bar
	by masterid: gen flag = (year > minyear) & (year < maxyear) & concatid == ""
	by masterid: egen donut = max(flag)

	drop foo bar

	keep if donut == 1
	keep masterid 
	duplicates drop


	tempfile donutlist
	save `donutlist'

restore 

merge m:1 masterid using `donutlist', assert(master match) gen(donutmerge)
gen donut = donutmerge == 3
drop donutmerge

*saving our donut-identified version of the panel 
save "hmda_harmonizer_panel", replace 

/*SUBSECTION 3: MATCHING DONUTS ONTO INFORMATION FROM THE AVERY FILE***********/
keep if donut == 1

*setting aside banks that are not identified by RSSD - we match these onto Avery file 
*later 
preserve 

	keep if rssd == .
	
	*all these banks have either an unchanging pre-2017 ID, an unchanging LEI, or both.
	*so we can create a variable holding each of these and use them as a merge key for 
	*the avery file 
	
	gen concatid = ""
	order concatid
	forvalues x = 2010/2017 {
		replace concatid = concatid`x' if concatid == ""
	}
	
	gen lei = masterid if concatid == ""
	
	tempfile donuts2 
	save `donuts2'

restore 

drop if rssd == .
tempfile tempdonuts 
save `tempdonuts'

use "avery_file/hmdpanel17.dta", clear
keep hmprid code RSSD10 RSSD11 RSSD12 RSSD13 RSSD14 RSSD15 RSSD16 RSSD17 ///
APPL10 APPL11 APPL12 APPL13 APPL14 APPL15 APPL16 APPL17 ///
ORIG10 ORIG11 ORIG12 ORIG13 ORIG14 ORIG15 ORIG16 ORIG17 ///
ORIGD10 ORIGD11 ORIGD12 ORIGD13 ORIGD14 ORIGD15 ORIGD16 ORIGD17 ///
ASSETL10 ASSETL11 ASSETL12 ASSETL13 ASSETL14 ASSETL15 ASSETL16 ASSETL17 ///
ASSETS10 ASSETS11 ASSETS12 ASSETS13 ASSETS14 ASSETS15 ASSETS16 ASSETS17

tostring code, replace
gen concatid = code + hmprid  

order concatid RSSD10 RSSD11 RSSD12 RSSD13 RSSD14 RSSD15 RSSD16 RSSD17 ///
APPL10 APPL11 APPL12 APPL13 APPL14 APPL15 APPL16 APPL17 ///
ORIG10 ORIG11 ORIG12 ORIG13 ORIG14 ORIG15 ORIG16 ORIG17 ///
ORIGD10 ORIGD11 ORIGD12 ORIGD13 ORIGD14 ORIGD15 ORIGD16 ORIGD17 ///
ASSETL10 ASSETL11 ASSETL12 ASSETL13 ASSETL14 ASSETL15 ASSETL16 ASSETL17 ///
ASSETS10 ASSETS11 ASSETS12 ASSETS13 ASSETS14 ASSETS15 ASSETS16 ASSETS17
 
*renaming variables to have years represented as 2010, not 10, 2011, not 11, etc
ren *1* *201*
ren *1201* *2011

*we'll want to return to this file later when we merge the banks not identified by RSSD 
tempfile moddedavery 
save `moddedavery'

*looping merge - for a given year of the Avery file, keep only the variables for
*that year, merge onto the donuts file, move on to the next year. At the end,
*we'll have the application, asset, origination, and origination value data
*for each donut bank in each year 
forvalues x = 2010/2017 {
	preserve 
	
		keep *`x'
		ren RSSD`x' rssd 
		
		*cleaning up RSSDs
		drop if rssd == . | rssd == 0
		duplicates tag rssd, gen(flag)
		drop if flag > 0
		drop flag 
		
		merge 1:1 rssd using `tempdonuts', gen(averymerge`x')
		drop if averymerge`x' == 1
		save `tempdonuts', replace 
	
	restore
} 


*do the same with the 2018 and 2019 Avery files
forvalues x = 18/19 {
	local y = `x' + 2000
	use "avery_file/hmda_panel_`y'.dta", clear 
	ren *`x' *20`x'
	keep APPL`y' ORIG`y' ORIGD`y' ASSETL`y' ASSETS`y' LEI
	ren LEI concatid`y'
	merge 1:m concatid`y' using `tempdonuts', gen(averymerge`y')
	drop if averymerge`y' == 1
	save `tempdonuts', replace 
}


*returning to the banks we set aside earlier - we'll repeat the same procedure 
*but match on different ID variables  
use `moddedavery', clear 

*looping merge - for a given year of the Avery file, keep only the variables for
*that year, merge onto the donuts file, move on to the next year. At the end,
*we'll have the application, asset, origination, and origination value data
*for each donut bank in each year 
forvalues x = 2010/2017 {
	preserve 
	
		keep concatid *`x'
		ren RSSD`x' rssd 
		
		merge 1:m concatid using `donuts2', gen(averymerge`x')
		drop if averymerge`x' == 1
		save `donuts2', replace 
	
	restore
} 

*do the same with the 2018 and 2019 Avery files
forvalues x = 18/19 {
	local y = `x' + 2000
	use "avery_file/hmda_panel_`y'.dta", clear 
	ren *`x' *20`x'
	keep APPL`y' ORIG`y' ORIGD`y' ASSETL`y' ASSETS`y' LEI 
	ren LEI lei
	merge 1:m lei using `donuts2', gen(averymerge`y')
	drop if averymerge`y' == 1
	save `donuts2', replace 
}

use `tempdonuts', clear
append using `donuts2'
*dropping the variables we made to merge `donuts2' onto the Avery file 
drop concatid lei

order rssd name* concatid* *2010 *2011 *2012 *2013 *2014 *2015 *2016 *2017 *2018 *2019
order concatid2018 concatid2019, after(concatid2017)

*checking that we matched every bank to at least one year of Avery file data
assert averymerge2010 == 3 | averymerge2011 == 3 | averymerge2012 == 3 | averymerge2013 == 3 | ///
averymerge2014 == 3 | averymerge2015 == 3 | averymerge2016 == 3 | averymerge2017 == 3 | averymerge2018 == 3 | ///
averymerge2019 == 3

/*SUBSECTION 4: USING INFORMATION FROM THE AVERY FILE TO IDENTIFY RSSD SWITCHERS*/
 
egen meanassets = rowmean(ASSETS*)
egen meanassetl = rowmean(ASSETL*)
*we type "ORIG2*" to avoid accidentally selecting "ORIGD*" variables
egen meanorig = rowmean(ORIG2*)
egen maxorig = rowmax(ORIG2*)
egen minorig = rowmin(ORIG2*)
egen meanorigd = rowmean(ORIGD*)

order masterid rssd metaid prepostmerge mean* maxorig minorig concatid*

*4.d
*first, we'll drop all banks that never originate 100 mortgages in a year 
*from our sample of banks to audit. This is consistent with HMDA rules indicating that 
*a bank is required to report to HMDA if it originates at least 100 closed-end
*mortgage loans or 500 open-end lines of credit 
 
drop if maxorig < 100
gsort -meanorigd //descending sort, so biggest banks get prioritized

*now, we audit manually, searching in the main panel for suitable candidates to 
*fill the "hole" for each donut. 

*my notes on this process/why I am correcting these masterid codes
*are in Appendix B of the documentation

use "hmda_harmonizer_panel", clear

*Implementing changes:

replace masterid = "112837" if masterid == "2253891"
replace donut = 0 if masterid == "112837"

replace masterid = "959304" if masterid == "3597239"
replace donut = 0 if masterid == "959304"

replace masterid = "3913633" if masterid == "391633"
replace donut = 0 if masterid == "3913633"

replace masterid = "1216826" if masterid == "4424136"
replace donut = 0 if masterid == "1216826"

replace masterid = "2860459" if masterid == "A104"
replace donut = 0 if masterid == "2860459"

replace masterid = "672984" if masterid == "1018945"
replace donut = 0 if masterid == "672984"

save "hmda_harmonizer_panel", replace 

/*SECTION 5. FINAL ADJUSTMENTS: ADDING LENDERS IN LOAN DATA BUT NOT PANELS, QUALITY CHECKS********/

*5.a
*ADDING LENDERS IN LOAN-LEVEL DATA BUT NOT PANELS

*Separately, I've merged the HMDA lender panels onto the loan-level data, and 
*I've found that there are several rare cases in which a lender appears in the 
*loan-level data but not the lender panels. Here, we add those HMDA IDs 
*into our panel of identifiers so that we can ID those loans. 

*2013: concatid 984-1542642
*I have confirmed that the loans corresponding to this concatid all occur in 
*Colorado, and the bank with this concatid in the previous year is in Colorado. 
*Identifies 839 loans.
replace concatid2013 = "984-1542642" if masterid == "2925929"

*2014: concatid 741-1795868
*This is a large number of loans - I believe these correspond to Ditech, a nationwide
*lender. Ditech's nationwide activity prevents me from checking that these loans 
*occur in one state that matches the lender. In a communication with HMDA, they
*have confirmed that this is the appropriate lender corresponding to this concatid
replace concatid2014 = "741-1795868" if masterid == "3861163"

*CLEAN-UP AND QUALITY CHECK

*is each concatid unique in each year?
forvalues i = 2010/2021 {
	preserve 
		drop if concatid`i' == ""
		isid concatid`i'
	restore 
}

*Dropping variables that were useful while coding but ultimately unneccessary in the 
*final panel 
drop agencycode* respondentid* parentrssdid* merge* 

*All the banks with prepostmerge missing only exist post-2017 
replace prepostmerge = 2 if prepostmerge == .
order prepostmerge, last
save "hmda_harmonizer_panel", replace  

*5.d
/*ADDING IN POST-2017 BANKS THAT WERE NOT INCLUDED IN HMDA LENDER PANELS*/
*After attempting to merge the crosswalk above onto the HMDA loan-level data,
*I find that there are 138 banks that appear in the loan-level data, but not
*the HMDA lender panels we used to construct our ID crosswalk.

*Those banks all appear in the post-2017 data and thus come with LEIs. Here,
*I try to link those LEIs back to RSSDs, and then add these banks into our 
*ID crosswalk. 

*I will perform the following steps:
	*Attempt to merge these banks onto RSSDs in the NIC Active dataset 
	*Attempt to merge these banks onto RSSDs in the NIC Closed dataset 
	*Attempt to merge these banks onto RSSDs in the Avery file
	*Attempt to merge these banks onto banks already in the crosswalk, since
		*some of them might already appear and just aren't in the lender panels
	*Use LEI as the masterid to identify remaining banks
	*Merge this subset of banks onto the main panel

use "banks_not_in_lender_panel", clear 

forvalues i = 2018/2021 {
	assert lei`i' == lei if lei`i' != ""
}

tempfile missinglei
save `missinglei'

*Merge these banks onto RSSDs in NIC Active Dataset
import delimited "nic/CSV_ATTRIBUTES_ACTIVE.CSV", clear

ren id_lei lei 
drop if lei == "0" 
keep lei id_rssd
merge 1:1 lei using `missinglei', keep(using match) nogen

save `missinglei', replace 

*Merge these banks onto RSSDs in NIC Closed Dataset
import delimited "nic/CSV_ATTRIBUTES_CLOSED.CSV", clear

ren id_lei lei 
drop if lei == "0"
keep lei id_rssd
merge 1:1 lei using `missinglei', keep(using match) nogen

*Merge these banks onto RSSDs in the 2018 Avery file
ren lei LEI
merge 1:1 LEI using "avery_file/hmda_panel_2018", keep(master match) nogen keepusing(RSSD18)

*Merge these banks onto RSSDs in the 2019 Avery file
merge 1:1 LEI using "avery_file/hmda_panel_2019", keep(master match) nogen keepusing(RSSD19)
ren LEI lei

*Merge these banks onto banks that already appear in the crosswalk 
*To keep it simple, only use banks that haven't already matched to an lei 

save `missinglei', replace 

drop if id_rssd != . | (RSSD18 != . & RSSD18 != 0) | (RSSD19 != . & RSSD19 != 0)
keep lei* 
tempfile missingleisubset
save `missingleisubset' 

forvalues i = 2018/2021 {
	use "hmda_harmonizer_panel", clear 
	keep if concatid`i' != ""
	ren concatid`i' lei
	keep masterid lei
	
	if `i' == 2018 {
	tempfile preppanel 
	}
	save `preppanel', replace 
	*Performing an update/replace merge to make sure the variable isn't overwritten
	use `missingleisubset', clear
	merge 1:1 lei using `preppanel', update replace gen(merge`i') keep(1 3 4 5)
	assert merge`i' != 5
	save `missingleisubset', replace 
}

*merging back onto the full set of banks that were missing from the lender panels
drop merge* 
merge 1:1 lei using `missinglei', assert(using match)

*Cleanup - we need these banks to have concatids for each year matched back to a masterid 

*First, make sure none of the RSSDs are conflicting 
replace RSSD18 = . if RSSD18 == 0
replace RSSD19 = . if RSSD19 == 0
assert id_rssd == RSSD18 if id_rssd != . & RSSD18 != .
assert id_rssd == RSSD19 if id_rssd != . & RSSD19 != .
assert RSSD18 == RSSD19 if RSSD18 != . & RSSD19 != .

*Arbitrarily, declare RSSD18 to be the "base" of the RSSD variable
gen rssd = RSSD18 
replace rssd = RSSD19 if RSSD19 != .
replace rssd = id_rssd if id_rssd != .
count if rssd == . & masterid == ""

tostring rssd, replace 
replace rssd = "" if rssd == "."
replace masterid = rssd if rssd != ""

*If a bank does not yet have a masterid, we do what we've done above and use lei 
*as masterid 
replace masterid = lei if masterid == ""

keep masterid lei* 
drop lei
ren lei* concatid*

*Now, we merge these banks onto the main panel
save `missinglei', replace 
use "hmda_harmonizer_panel", clear 
merge m:1 masterid using `missinglei', update replace assert(1 2 4)

replace donut = 0 if _merge == 2 //I checked - none of these are donuts
replace prepostmerge = 2 if _merge == 2 //these are all post-2017, didn't match to a pre-2017 bank
drop _merge 

save "hmda_harmonizer_panel", replace  

*Finally, we want to see whether we can gain any information from the 2020 and 2021
*versions of the Avery file:
	
use "avery_file/hmda_panel_2020", clear
ren LEI concatid2020
ren RSSD20 rssdavery 
tempfile avery20 
save `avery20'

use "avery_file/hmda_panel_2021", clear 
ren LEI concatid2021
ren RSSD21 rssdavery 
tempfile avery21
save `avery21'

*We begin with the 2020 Avery file data

/*Merge on the 2020 Avery file, and generate a variable that flags when
*a given LEI has different RSSDs in our panel and in the Avery file*/
use "hmda_harmonizer_panel", clear
keep if concatid2020 != ""
merge 1:1 concatid2020 using `avery20'
	
gen flag = (rssd != rssdavery) & (rssdavery != 0) & (rssdavery != .)	
order flag masterid rssd rssdavery
sort flag
keep if flag == 1

keep rssdavery concatid2020
ren rssdavery rssd 
gen masterid = concatid2020 
tempfile concatidcheck 
save `concatidcheck'

*Now that we have this subset of banks where LEI/RSSD is different in each panel, 
*there are two possibilities for each bank:
	*The Avery file provides an RSSD where we previously had none (most cases)
		*When this happens, we also need to check that the bank for which we're hoping to 
		*fill in an RSSD doesn't already exist in our dataset as an LEI-identified bank
	*There's a disagreement between the RSSDs on file in the Avery file and our file.
	
*Our plan is as follows:
*Take the 35 banks that flagged above. Using masterid = LEI, merge them back onto 
*the main panel.
	*First, look at the 30 _merge == 4 observations - these cases are "missing updated",
	*meaning that we've taken banks that were previously only identified with LEI, and have now
	*added an RSSD.
	*We take those _merge == 4 observations, declare masterid == RSSD, then 
	*merge back onto the main panel as a way to check whether this RSSD was already 
	*in use. In the case of these 30 observations, we only get _merge == 2 (the RSSD was
	*not in use) or _merge == 4 (the RSSD was in use and we've just populated the
	*concatid2020 variable where it was once empty).
	
	*Then, look at the 5 _merge == 2 observations. These cases are instances are 
	*"using only", meaning there is no row with masterid == LEI for these banks,
	*and suggesting that this LEI is already on record under a different RSSD.
	*We will show that when this happens, our RSSD-LEI pairings are supported by the 
	*original HMDA lender panel.

	
use "hmda_harmonizer_panel", clear
merge m:1 masterid using `concatidcheck', update
sort _merge
order _merge
tab _merge 
tempfile working2020
save `working2020'

keep if _merge == 4
keep rssd concatid2020 
tostring rssd, gen(masterid)
tempfile check2020
save `check2020'
use "hmda_harmonizer_panel", clear
merge m:1 masterid using `check2020', update replace 
sort _merge
order _merge

*Ignoring our planned _merge == 1's, we got all _merge == 2's and 4's, suggesting 
*we're either filling in an already-existing time series associated with an RSSD, 
*or we're adding RSSDs to the panel. That is, there are no RSSD-LEI conflicts.

*Saving a tempfile so we can append on these new rows later

keep if _merge != 1
tempfile tomerge2020
save `tomerge2020'

*We just handled 30/35 of the flagged banks from 2020. Next, look at the remaining 5 _merge == 2 observations.
use `working2020'
keep if _merge == 2

*Here, I manually audited the remaining five banks. Two of them, with LEI codes:
*5493001R92DY5DI1DI85 and 5493003QF1L7XNSWRM19, we've already manually recoded above,
*and the RSSD in the Avery file actually matches the masterid we manually assigned.

*The other 3, with LEI codes: 549300SCFWZXMDMZPE93, 549300S5NLOTO329NX77, and 5493000YNV8IX4VD3X12,
*I manually confirm have the same RSSD in our masterid and in the lender panel (we disagree with the Avery file).
*No changes made for these banks.

*Now, we repeat the procedure for the 2021 Avery file:
/*Merge on the 2021 Avery file, and generate a variable that flags when
*a given LEI has different RSSDs in our panel and in the Avery file*/
use "hmda_harmonizer_panel", clear
keep if concatid2021 != ""
merge 1:1 concatid2021 using `avery21'
	
gen flag = (rssd != rssdavery) & (rssdavery != 0) & (rssdavery != .)	
order flag masterid rssd rssdavery
sort flag
keep if flag == 1

keep rssdavery concatid2021
ren rssdavery rssd 
gen masterid = concatid2021
tempfile concatidcheck 
save `concatidcheck'

use "hmda_harmonizer_panel", clear
merge m:1 masterid using `concatidcheck', update
sort _merge
order _merge
tab _merge 
tempfile working2021
save `working2021'

keep if _merge == 4
keep rssd concatid2021
tostring rssd, gen(masterid)
tempfile check2021
save `check2021'
use "hmda_harmonizer_panel", clear
merge m:1 masterid using `check2021', update replace 
sort _merge
order _merge

*Ignoring our planned _merge == 1's, we got all _merge == 2's and 4's, suggesting 
*we're either filling in an already-existing time series associated with an RSSD, 
*or we're adding RSSDs to the panel. That is, there are no RSSD-LEI conflicts.

*Now, we just need to remove any rows associated with these LEIs in 2020 
*in the main panel, so we don't duplicate them when we add these improved rows later

keep if _merge != 1
*Saving a tempfile so we can append on these new rows
tempfile tomerge2021
save `tomerge2021'

*Next, look at the remaining _merge == 2 observations.
use `working2021'
keep if _merge == 2

*Once again, let's check this against the lender panel for 2021 - too many banks
*to do manually this time:

keep masterid concatid2021 rssd 
ren concatid2021 lei
merge 1:1 lei using "hmda_lender_panels/2021_public_panel_csv.dta", keep(match)
assert rssd != respondent_rssd

*Once again, all remaining banks are points of disagreement between us and the Avery file,
*we don't alter RSSD-LEI pairs for these banks since our pairings match those in the lender panel

*So now, all that's left to do is add our newly RSSD-identified banks into the main panel.
clear
use `tomerge2020'
append using `tomerge2021'
tempfile lateadditions
save `lateadditions'
*Once again, we have two groups of banks here:
*	1) banks where we're populating concatid2020/2021 for an RSSD we already had in the panel (_merge == 4)
*	2) banks where we're adding new RSSDs to the dataset (_merge == 2)

*Handling the first type:
	keep if _merge == 4

	*We have some duplicate rows, from banks where we gained RSSD info from both the 
	*2020 and 2021 Avery files. Collapsing down here:
	keep masterid concatid2020 concatid2021
	collapse (firstnm) concatid*, by(masterid)

	*We'll merge these banks on three times:
		*First, to identify and delete any rows identified by the LEI in concatid2020 
		*Second, to identify and delete any rows identified by the LEI in concatid2021
		*Finally, an update merge to fill the holes in the time series for these RSSDs in the main panel 
	preserve
		replace masterid = concatid2020 
		keep if masterid != ""
		merge 1:m masterid using "hmda_harmonizer_panel", keep(using) nogen 
		save "hmda_harmonizer_panel", replace 
	restore
	preserve
		replace masterid = concatid2021
		keep if masterid != ""
		merge 1:m masterid using "hmda_harmonizer_panel", keep(using) nogen 
		save "hmda_harmonizer_panel", replace
	restore 

	*before we merge on to the main panel, let's create and populate the name2020/2021
	*variables 
	gen lei = concatid2020 
	merge m:1 lei using "hmda_lender_panels/2020_public_panel_csv.dta", keep(master match) keepusing(respondent_name) nogen
	ren respondent_name name2020 
	replace lei = concatid2021 
	merge m:1 lei using "hmda_lender_panels/2020_public_panel_csv.dta", keep(master match) keepusing(respondent_name) nogen
	ren respondent_name name2021
	drop lei
	*we have to have the main panel as the master to perform the update merge 
	tempfile type1
	save `type1'
	use "hmda_harmonizer_panel", clear 
	merge m:1 masterid using `type1', update nogen
	save "hmda_harmonizer_panel", replace 

*Handling the second type:
	use `lateadditions', clear 
	keep if _merge == 2
	
	*We have some duplicate rows, from banks where we gained RSSD info from both the 
	*2020 and 2021 Avery files. Collapsing down here:
	keep masterid concatid2020 concatid2021
	collapse (firstnm) concatid*, by(masterid)
	
	*Here, we don't want to destroy the already-existing rows in our main panel that are LEI-identified,
	*we just want to update them with the new rssds 
	destring masterid, gen(rssd_to_add)
	replace masterid = concatid2021 
	replace masterid = concatid2020 if masterid == ""
	
	tempfile type2 
	save `type2'
	use "hmda_harmonizer_panel", clear 
	merge m:1 masterid using `type2', update 
	replace masterid = "" if _merge == 3
	replace rssd = rssd_to_add if _merge == 3
	tostring rssd_to_add, replace
	replace masterid = rssd_to_add if _merge == 3
	order concatid2020 concatid2021, after(concatid2019)
	drop _merge rssd_to_add
	
save "hmda_harmonizer_panel", replace 


/*Creating a "recoding" flag variable*/

/*This is a binary variable to flag cases where I've changed the relationship 
between a HMDA ID/LEI and an RSSD according to personal judgement, or manually
changed a bank's masterid*/
gen recoding_flag = 0
#delimit ;
foreach x in 
"3343717" "4320395" "568443" //2.a.i
"3075401" //2.b.ii.5
"3874118" "4327965" //2.b.ii.8
"102379" //2.c.iii.1
"867856" "3383665" //3.e.ii.2
"5019678" "3876710" "980951" "649397" "64897" //3.f
"3310456" "3878750" "111205" "251978" "61122"
"200378" "2760232" "754929" "3195242" "713926"
"968557" "977951"
"4455073" "2351078" "3844492" "3882560" "3950469" //4.a.v-4.a.vi 
"3876390" "2383060" "3715220" "3720532"
"112837" "959304" "3913633" "1216826" "2860459" "672984" //4.d
{; 
	replace recoding_flag = 1 if masterid == "`x'";
};
#delimit cr 
save "hmda_harmonizer_panel", replace 
