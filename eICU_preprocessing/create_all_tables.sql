-- creates all the tables and produces csv files
-- takes a while to run (about an hour)

-- change the paths to those in your local computer using find and replace for 'C:/Users/mcevo/Documents/UIUC/CS 598 Deep Learning for Healthcare/Project/Data/eicu-collaborative-research-database-2.0/preprocessed/eicu/'.
-- keep the file names the same

\i eICU_preprocessing/labels.sql
\i eICU_preprocessing/diagnoses.sql
\i eICU_preprocessing/flat_features.sql
\i eICU_preprocessing/timeseries.sql

-- we need to make sure that we have at least some form of time series for every patient in diagnoses, flat and labels
drop materialized view if exists ld_timeseries_patients cascade;
create materialized view ld_timeseries_patients as
  with repeats as (
    select distinct patientunitstayid
      from ld_timeserieslab
    union
    select distinct patientunitstayid
      from ld_timeseriesresp
    union
    select distinct patientunitstayid
      from ld_timeseriesnurse
    union
    select distinct patientunitstayid
      from ld_timeseriesperiodic
    union
    select distinct patientunitstayid
      from ld_timeseriesaperiodic)
  select distinct patientunitstayid
    from repeats;

\copy (select * from ld_labels as l where l.patientunitstayid in (select * from ld_timeseries_patients)) to 'C:/Users/mcevo/Documents/UIUC/CS 598 Deep Learning for Healthcare/Project/Data/preprocessed/eicu/labels.csv' with csv header
\copy (select * from ld_diagnoses as d where d.patientunitstayid in (select * from ld_timeseries_patients)) to 'C:/Users/mcevo/Documents/UIUC/CS 598 Deep Learning for Healthcare/Project/Data/preprocessed/eicu/diagnoses.csv' with csv header
\copy (select * from ld_flat as f where f.patientunitstayid in (select * from ld_timeseries_patients)) to 'C:/Users/mcevo/Documents/UIUC/CS 598 Deep Learning for Healthcare/Project/Data/preprocessed/eicu/flat_features.csv' with csv header
\copy (select * from ld_timeserieslab) to 'C:/Users/mcevo/Documents/UIUC/CS 598 Deep Learning for Healthcare/Project/Data/preprocessed/eicu/timeserieslab.csv' with csv header
\copy (select * from ld_timeseriesresp) to 'C:/Users/mcevo/Documents/UIUC/CS 598 Deep Learning for Healthcare/Project/Data/preprocessed/eicu/timeseriesresp.csv' with csv header
\copy (select * from ld_timeseriesnurse) to 'C:/Users/mcevo/Documents/UIUC/CS 598 Deep Learning for Healthcare/Project/Data/preprocessed/eicu/timeseriesnurse.csv' with csv header
\copy (select * from ld_timeseriesperiodic) to 'C:/Users/mcevo/Documents/UIUC/CS 598 Deep Learning for Healthcare/Project/Data/preprocessed/eicu/timeseriesperiodic.csv' with csv header
\copy (select * from ld_timeseriesaperiodic) to 'C:/Users/mcevo/Documents/UIUC/CS 598 Deep Learning for Healthcare/Project/Data/preprocessed/eicu/timeseriesaperiodic.csv' with csv header