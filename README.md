# hmda_harmonizer
Project to create a multi-year crosswalk for HMDA ID codes

# Abstract

The Home Mortgage Disclosure Act (HMDA) dataset is a government publication, containing information information from thousands of lenders about tens of millions of mortgages and mortgage applications each year. It is one of the best public resources for studying mortgage lending in the United States. HMDA contains identifying information that enables researchers to study the lending behavior of individual banks. However, HMDA is published in yearly installments, and the codes used to identify lenders can change between years. This makes it difficult to perform studies that require consistently identifying the same lender in multiple years of the dataset - for instance, in regressions using multiple years of HMDA data with fixed effects for individual banks.

This GitHub repository is a replication package for a novel multi-year identifier panel. Every bank that files a HMDA report from 2010-2021 is assigned a unique, time-invariant code that is linked to the identifier for that bank in HMDA in each year. This solves the problem described above by providing one harmonized code to track individual banks in HMDA, even if a bank’s identifier in the HMDA data changes between years.

The package contains the final panel dataset, code to replicate the dataset, and accompanying documentation explaining the code and the underlying rationale and methodology. 

# Contents:

Documentation for HMDAHarmonizer.docx: Contains full documentation for everything in this folder

hmda_harmonizer_panel.dta: Final product of this replication package, a multi-year crosswalk for HMDA ID codes

hmda_harmonizer.do: Contains script to replicate the hmda_harmonizer_panel.dta file

Sources.docx: Contains instructions for downloading raw inputs for the hmda_harmonizer.do file

banks_not_in_crosswalk.dta: Supplementary file called during the execution of hmda_harmonizer.do, containing the LEI codes for banks that appear in the HMDA loan-level data but not in the corresponding lender panel. See page 7 of the documentation for details

# Contact:
Zach Babat
zachbabat1 [at] gmail [dot] com 
