*demo_code.do

*This code demonstrates how to use the hmda_harmonizer_panel dataset to identify
*loans in the HMDA loan-level data.

*Note that the execution of this script requires downloading the HMDA loan-level
*datasets. This is not a required step to execute the replication of the HMDAHarmonizer
*panel itself. A guide for taking the optional step of finding and downloading the 
*loan-level datasets can be found on page 3 of Sources.docx.

*This script assumes the loan-level datasets have all been downloaded and saved 
*as .dta files.

forvalues i = 2010/2017 {
	use hmda_harmonizer
	keep masterid concatid`i'
	keep if concatid`i' != ""
	
	*in the next three lines, we break the concatid variables out into their component parts:
	*agency codes and respondent ids, both of which are needed to match loan observations back
	*to their lenders
	gen agency_code = substr(concatid`i', 1, 1)
	destring agency_code, replace
	gen respondent_id = substr(concatid`i', 2, .)
	
	merge 1:m respondent_id agency_code using "hmda_`i'_nationwide_all-records_labels.dta"
	save "master_xwalk_identified_lar_`i'", replace
	clear
}

forvalues i = 2018/2021 {
	use hmda_harmonizer
	keep masterid concatid`i'
	keep if concatid`i' != ""
	
	*in the post-2018 data, concatid needs no processing beyond variable renaming before use
	ren concatid`i' lei
	
	merge 1:m lei using "original_hmda/dta_versions/`i'_lar.dta", gen(masterxwalkmerge)
	save "merged_panel_and_loan_level/master_xwalk_identified_lar_`i'", replace
	clear
}