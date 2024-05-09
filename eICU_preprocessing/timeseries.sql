-- MUST BE RUN AFTER labels.sql

-- creates a materialized view commonlabs which looks like this:
/*
         labname          | count
--------------------------+-------
 creatinine               | 85862
 sodium                   | 85802
 potassium                | 85770
 BUN                      | 85727
*/

-- creates a materialized view timeserieslab which looks like this:
/*
 patientunitstayid | labresultoffset |         labname          |  labresult
-------------------+-----------------+--------------------------+--------------
            141194 |             312 | total protein            |       6.9000
            141194 |             667 | lactate                  |       1.0000
            141194 |            1360 | bedside glucose          |     109.0000
            141194 |             312 | glucose                  |     165.0000
*/

-- creates a materialized view commonresp which looks like this:
/*
 respchartvaluelabel | count
---------------------+-------
 FiO2                | 37936
 RR (patient)        | 25358
 PEEP                | 24223
 TV/kg IBW           | 21909
*/

-- creates a materialized view timeseriesresp which looks like this:
/*
 patientunitstayid | respchartoffset | respchartvaluelabel | respchartvalue
-------------------+-----------------+---------------------+----------------
            158712 |           -1365 | FiO2                | 55
            172049 |             916 | Total RR            | 13
            172049 |             916 | FiO2                | 35
            172049 |             916 | Vent Rate           | 10

*/

-- creates a materialized view timeseriesperiodic which looks like this:
/*
 patientunitstayid | observationoffset | temperature | sao2 | heartrate | respiration | cvp | systemicsystolic | systemicdiastolic | systemicmean | st1 | st2 | st3
-------------------+-------------------+-------------+------+-----------+-------------+-----+------------------+-------------------+--------------+-----+-----+-----
            141168 |               119 |             |   93 |       140 |             |     |                  |                   |              |     |     |
            141168 |               124 |             |      |       140 |             |     |                  |                   |              |     |     |
            141168 |               129 |             |      |       140 |             |     |                  |                   |              |     |     |
            141168 |               134 |             |      |       140 |             |     |                  |                   |              |     |     |
*/

-- creates a materialized view timeseriesaperiodic which looks like this:
/*
 patientunitstayid | observationoffset | noninvasivesystolic | noninvasivediastolic | noninvasivemean
-------------------+-------------------+---------------------+----------------------+-----------------
            141168 |               123 |                 106 |                   68 |              81
            141168 |               138 |                 111 |                   62 |              82
            141168 |               349 |                     |                      |              79
            141168 |               441 |                     |                      |              62
*/

-- extract the most common lab tests and the corresponding counts of how many patients have values for those labs
drop materialized view if exists ld_commonlabs cascade;
create materialized view ld_commonlabs as
  select labsstay.labname, count(distinct la.patientunitstayid) as count
    -- we choose between -1440 and discharge offset rather than between 0 and discharge offset because we also want to
    -- consider the labs recorded before the unit time starts because these might contribute to the data once the
    -- missing values have been imputed forwards
    from (
      select l.labname, l.patientunitstayid
        from lab as l
        inner join patient as p
          on p.patientunitstayid = l.patientunitstayid
        where labresultoffset between -1440 and p.unitdischargeoffset
      ) as labsstay
    inner join ld_labels as la
      on la.patientunitstayid = labsstay.patientunitstayid
    group by labsstay.labname
    -- only keep data that is present at some point for at least 25% of the patients, this gives us 47 lab features
    having count(distinct la.patientunitstayid) > (select count(distinct patientunitstayid) from ld_labels)*0.25
    order by count desc;

-- get the time series features from the most common lab tests (46 of these)
drop materialized view if exists ld_timeserieslab cascade;
create materialized view ld_timeserieslab as
  select l.patientunitstayid, l.labresultoffset, l.labname, l.labresult
    from lab as l
    inner join patient as p
      on p.patientunitstayid = l.patientunitstayid
    inner join ld_commonlabs as cl
      on cl.labname = l.labname  -- only include the common labs
    inner join ld_labels as la
      on la.patientunitstayid = l.patientunitstayid  -- only extract data for the cohort
    where l.labresultoffset between -1440 and p.unitdischargeoffset;

-- extract the most common respiratory chart entries and the corresponding counts of how many patients have values for
-- those respiratory charts
drop materialized view if exists ld_commonresp cascade;
create materialized view ld_commonresp as
  select respstay.respchartvaluelabel, count(distinct la.patientunitstayid) as count
    -- we choose negative offsets as well because we also want to consider the respiratory data recorded before the
    -- unit time starts because these might contribute to the data once the missing values have been imputed forwards
    from (
      select r.respchartvaluelabel, r.patientunitstayid
        from respiratorycharting as r
        inner join patient as p
          on p.patientunitstayid = r.patientunitstayid
        where respchartoffset between -1440 and p.unitdischargeoffset
      ) as respstay
    inner join ld_labels as la
      on la.patientunitstayid = respstay.patientunitstayid
    group by respstay.respchartvaluelabel
    -- only keep data that is present at some point for at least 12.5% of the patients
    -- (less stringent because fewer patients are ventilated) but it is informative if they are
    having count(distinct la.patientunitstayid) > (select count(distinct patientunitstayid) from ld_labels)*0.125
    order by count desc;

-- get the time series features from the most common respiratory chart entries (14 of these)
drop materialized view if exists ld_timeseriesresp cascade;
create materialized view ld_timeseriesresp as
  select r.patientunitstayid, r.respchartoffset, r.respchartvaluelabel, r.respchartvalue
    from respiratorycharting as r
    inner join ld_commonresp as cr
      on cr.respchartvaluelabel = r.respchartvaluelabel  -- only include the common respiratory chart values
    inner join ld_labels as la
      on la.patientunitstayid = r.patientunitstayid  -- only extract data for the cohort
    inner join patient as p
      on p.patientunitstayid = r.patientunitstayid
    where r.respchartoffset between -1440 and p.unitdischargeoffset;

-- extract the most common nurse chart entries and the corresponding counts of how many patients have values for those
-- nurse charts
drop materialized view if exists ld_commonnurse cascade;
create materialized view ld_commonnurse as
  select nursestay.nursingchartcelltypevallabel, count(distinct la.patientunitstayid) as count
    -- we choose negative offsets as well because we also want to consider the nursecharting data recorded before the
    -- unit time starts because these might contribute to the data once the missing values have been imputed forwards
    from (
      select n.nursingchartcelltypevallabel, n.patientunitstayid
        from nursecharting as n
        inner join patient as p
          on p.patientunitstayid = n.patientunitstayid
        where nursingchartoffset between -1440 and p.unitdischargeoffset
      ) as nursestay
    inner join ld_labels as la
      on la.patientunitstayid = nursestay.patientunitstayid
    group by nursestay.nursingchartcelltypevallabel
    -- only keep data that is present at some point for at least 25% of the patients
    having count(distinct la.patientunitstayid) > (select count(distinct patientunitstayid) from ld_labels)*0.125
    order by count desc;

-- get the time series features from the most common nursing chart entries
drop materialized view if exists ld_timeseriesnurse cascade;
create materialized view ld_timeseriesnurse as
  select n.patientunitstayid, n.nursingchartoffset, n.nursingchartcelltypevallabel, n.nursingchartvalue
    from nursecharting as n
    inner join ld_commonnurse as cn
      on cn.nursingchartcelltypevallabel = n.nursingchartcelltypevallabel  -- only include the common chart values
    inner join ld_labels as la
      on la.patientunitstayid = n.patientunitstayid  -- only extract data for the cohort
    inner join patient as p
      on p.patientunitstayid = n.patientunitstayid
    where n.nursingchartoffset between -1440 and p.unitdischargeoffset;

-- get the periodic (regularly sampled) time series data
-- see tester queries in the comments at the bottom to see how these features were chosen
drop materialized view if exists ld_timeseriesperiodic cascade;
create materialized view ld_timeseriesperiodic as
  select vp.patientunitstayid, vp.observationoffset, vp.temperature, vp.sao2, vp.heartrate, vp.respiration, vp.cvp,
    vp.systemicsystolic, vp.systemicdiastolic, vp.systemicmean, vp.st1, vp.st2, vp.st3
    from vitalperiodic as vp
    -- select only the patients who are in the cohort
    inner join ld_labels as la
      on la.patientunitstayid = vp.patientunitstayid
    inner join patient as p
      on p.patientunitstayid = vp.patientunitstayid
    where vp.observationoffset between -1440 and p.unitdischargeoffset
    order by vp.patientunitstayid, vp.observationoffset;

-- get the aperiodic (irregularly sampled) time series data
-- see tester queries in the comments at the bottom to see how these features were chosen
drop materialized view if exists ld_timeseriesaperiodic cascade;
create materialized view ld_timeseriesaperiodic as
    -- see tester queries at the bottom to see how these were chosen
    select va.patientunitstayid, va.observationoffset, va.noninvasivesystolic, va.noninvasivediastolic, va.noninvasivemean
    from vitalaperiodic as va
    -- select only the patients who are in the cohort
    inner join ld_labels as la
      on la.patientunitstayid = va.patientunitstayid
    inner join patient as p
      on p.patientunitstayid = va.patientunitstayid
    where va.observationoffset between -1440 and p.unitdischargeoffset
    order by va.patientunitstayid, va.observationoffset;

-- vitalperiodic: tester query to check which columns should be included
-- using a 13% cut off 89143*0.13 = 11588, then only sao2, heartrate, respiration, cvp, systemicsystolic,
-- systemicdiastolic, systemicmean, st1, st2 and st3 should be included
-- I am also keeping temperature because I think if it's being monitored then that's a sign there could be an infection
-- counts of patients who have values for various columns in vitalaperiodic:
-- temperature: 10323
-- sao2: 86096
-- heartrate: 86828
-- respiration: 80972
-- cvp: 15397
-- etco2: 4419
-- systemicsystolic: 24125
-- systemicdiastolic: 24123
-- systemicmean: 24284
-- pasystolic: 6263
-- padiastolic: 6266
-- pamean: 6307
-- st1: 41729
-- st2: 43174
-- st3: 40712
-- icp: 912
/*
select count(distinct vp.patientunitstayid)
  from vitalperiodic as vp
  inner join labels as la
    on vp.patientunitstayid = f.patientunitstayid
  where vp.st3 is not null and vp.observationoffset < 1440;
*/

-- vitalaperiodic: tester query to check which columns should be included
-- clearly it is only worth including noninvasivesystolic, noninvasivediastolic and noninvasivemean
-- counts of patients who have values for various columns in vitalaperiodic:
-- noninvasivesystolic: 84934
-- noninvasivediastolic: 84935
-- noninvasivemean: 84947
-- paop: 1046
-- cardiacoutput: 3022
-- cardiacinput: 2393
-- svr: 2998
-- svri: 2382
-- pvr: 996
-- pvri: 984
/*
select count(distinct va.patientunitstayid)
  from vitalaperiodic as va
  inner join labels as la
    on va.patientunitstayid = f.patientunitstayid
  where va.pvri is not null and va.observationoffset < 1440;
*/

