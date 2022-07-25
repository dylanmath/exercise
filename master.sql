/*
 * Whimsical Exercise - Editor Downgrades Analysis
 * Dylan Matthews
 * 25 July 2022
 */

-- Typical approach
-- 1. break down business question into pieces/steps
-- 2. note any assumptions made
-- 3. choose a way to deliver the answer to the question so it's easy to understand
-- 4. provide next steps or possible future analysis that will provide a better answer

/* ---------------------------------------------------------------------------------------------------------------------
 EDA & DATA PREP
 ---------------------------------------------------------------------------------------------------------------------*/

-- testing customer_id              => cus_FlITmAq73cfjp0
-- testing workspace_id             => c4f41d07-3da1-410f-8e21-d2805f325bed
-- testing subscription_ids         => sub_FlIT2JgGdOCck9, sub_1Ja5fBBx6rj3C0EgjSVoUkBu, sub_1Ja5hdBx6rj3C0EgPgGKI9QR


-- paid customers only
create or replace view dm_paid_customers_subscriptions_workspaces as
(
select  count(s.id)         as subscription_count,
        s.customer          as customer_id,
        s.paid              as paid_customer_flag,
        c.workspace_id      as workspace_id
from    dev.public.str_sub s
join    dev.public.str_cust c
on      s.customer = c.id
where   s.paid = True
-- and     s.customer = 'cus_FlITmAq73cfjp0'
group by 2, 3, 4
) with no schema binding;
-- drop view dm_paid_customers_subscriptions_workspaces
-- paid = true  => 16553
-- paid = false => 4233

-- get the distinct paid workspace ids
select  distinct(workspace_id)
from    dm_paid_customers_subscriptions_workspaces;
-- 15239

/* ---------------------------------------------------------------------------------------------------------------------
 QUESTION 1
 ----------
 When workspaces downgrade or remove editors, do they fully remove that member (suggesting that the person has left the
 organization or no longer needs to use Whimsical)? Alternatively, do they convert the editor to a viewer or guest
 (suggesting that the person may still be referencing Whimsical content, but just not editing it)?

 Translated/Steps:
 1. get all the users downgraded from editor and day/week/month they downgraded from clo_user_track_event
 2. get their current status fro clo_member_workspace
 3. calculate proportion of downgraded users that were deleted, viewer or guest of the total downgrades
 4. visualise in a monthly % over time

 1.
 ---------------------------------------------------------------------------------------------------------------------*/

-- testing the clo_user_track_event table
select  *
from    clo_user_track_event
where   event = 'workspace-member-status-change'
and     created >= '02/02/2022'
and     data is not null;
-- 126,140

-- test with 1 workspace that has several status changes => ws_id = '1458a541-b3f9-4631-aa5d-5fb3f3b2cc22'
select  *
from    clo_user_track_event
where   event = 'workspace-member-status-change'
and     created >= '02/02/2022'
and     data is not null
and     workspace_id = '1458a541-b3f9-4631-aa5d-5fb3f3b2cc22';
-- 1138

-- get the distinct data fields
select  distinct(data)
from    clo_user_track_event
where   event = 'workspace-member-status-change'
and     created >= '02/02/2022'
and     data is not null;
-- 23 records, but whitespaces creating duplication, so will need to remove

select  distinct(json_serialize(json_parse(data))) as change_event,
        count(*)
from    clo_user_track_event
where   event = 'workspace-member-status-change'
and     created >= '02/02/2022'
and     data is not null
group by change_event;
-- 14 change events, now need to split out each, double check with counts (sum is 126140 which we expect)


-- confirm the exclusion for member?: true
select  created,
        user_id,
        workspace_id,
        event,
        json_serialize(json_parse(data)),
        json_extract_path_text(data, 'editor?') as editor,
        json_extract_path_text(data, 'member?') as member,
        json_extract_path_text(data, 'admin?')  as admin
from    clo_user_track_event
where   workspace_id = '000d792d-83b5-4edd-bf0a-884fb3506de1'
and     event = 'workspace-member-status-change'
and     created >= '02/02/2022'
and     data is not null
and     json_extract_path_text(data, 'member?') != 'true'; -- use this per updated instructions


-- testing with 1 workspace
select  distinct(json_serialize(json_parse(data))) as change_event,
        count(*)
from    clo_user_track_event
where   event = 'workspace-member-status-change'
and     created >= '02/02/2022'
and     data is not null
and     json_extract_path_text(data, 'member?') != 'true'
and     workspace_id = '1458a541-b3f9-4631-aa5d-5fb3f3b2cc22'
group by change_event;

-- experiment and create a master view for the user editor downgrade events
create or replace view dm_editor_downgrades as (
select  max(created), -- get the max created editor downgrade for that user
        user_id,
        workspace_id,
        event,
        json_serialize(json_parse(data))
        -- json_extract_path_text(data, 'editor?') as editor,   -- don't need this
        -- json_extract_path_text(data, 'member?') as member,   -- don't need this
        -- json_extract_path_text(data, 'admin?')  as admin     -- don't need this
from    dev.public.clo_user_track_event
where   event = 'workspace-member-status-change'
and     created >= '02/02/2022'
and     data is not null
and     json_extract_path_text(data, 'member?') != 'true'
and     json_extract_path_text(data, 'editor?') = 'false'
group by 2, 3, 4, 5
) with no schema binding; -- limit directly on editor?: false
--and     workspace_id = '1458a541-b3f9-4631-aa5d-5fb3f3b2cc22';
-- 9280 Editor downgrades (without using max(created)
-- 7921 Editor downgrades (using max(created) => create a view and use this as master table

-- check the event logic, concerned with 'editor?: false' or editor = false, then check the user_id in clo_workspace_member
select  *
from    clo_user_track_event
where   user_id = '04484d1a-277f-4403-904c-b6372edc15ec'
and     event = 'workspace-member-status-change'
and     created >= '02/02/2022'
and     data is not null

-- editor false on 23/5/2022

select  *
from    clo_workspace_member
where   user_id = 'a542e444-edbc-4ab5-913c-a92fcf5769cc'
-- current viewer

-- based on manual checking, there is a strange duplication occuring (e.g. user_id = 04484d1a-277f-4403-904c-b6372edc15ec
-- and workspace_id = d667893e-77aa-4d71-958e-fca18567ef82), with 7 distinct event created dates for a single user_id,
-- workspace_id , event, data combination (e.g. would expect to see editor = false, then editor = true, not just editor = false x 7 rows)
-- Given we need to join to clo_workspace_member to determine whether downgraded Editor is a Viewer, Guest or Deleted, we
-- will assume the most recent (max) created date is Editor downgrade record that we want.

-- now that we have all the workspace editor downgrades, we can query the clo_workspace_member to get the current role (viewer, guest or deleted)
--


-- use the views to get results from the clo_workspace_member view
select  wm.workspace_id                                                 as workspace_id,
        wm.user_id                                                      as user_id,
        trunc(added)                                                    as member_added_to_workspace_date,
        trunc(deleted)                                                  as member_deleted_from_workspace_date,
        case when wm.editor = True  then 1 else 0 end                   as editor_flag,
        case when wm.guest = True   then 1 else 0 end                   as guest_flag,
        case when (wm.editor = False and wm.guest = False) then 1 end   as viewer_flag,
        case when wm.deleted is not null then 1 end                     as deleted_flag
from    clo_workspace_member wm
where   user_id in (select distinct(user_id) from dm_editor_downgrades)
and     workspace_id in (select distinct(workspace_id) from dm_paid_customers_subscriptions_workspaces);
and     wm.editor != True;

-- extract results and chart in excel for ease of use

select * from dm_editor_downgrades

select  wm.workspace_id                                                 as workspace_id,
        wm.user_id                                                      as user_id,
        trunc(added)                                                    as member_added_to_workspace_date,
        trunc(deleted)                                                  as member_deleted_from_workspace_date,
        case when wm.editor = True  then 1 else 0 end                   as editor_flag,
        case when wm.guest = True   then 1 else 0 end                   as guest_flag,
        case when (wm.editor = False and wm.guest = False) then 1 end   as viewer_flag,
        case when wm.deleted is not null then 1 end                     as deleted_flag,
        date_part('mon', ed.max)                                        as event_month
from    clo_workspace_member wm
join    dm_editor_downgrades ed on wm.user_id = ed.user_id
join    dm_paid_customers_subscriptions_workspaces pcsw on wm.workspace_id = pcsw.workspace_id
and     wm.editor != True;

/* ---------------------------------------------------------------------------------------------------------------------
 QUESTION 2
 ----------

 When users are downgraded to viewers or guests, how regularly do they continue to view Whimsical content?

 Translated/Steps:
 1. Get Editor downgrade user list and exclude deleted users
 2. Join to the clo_user_track_event table and filter by page-view event
 3. Regularity suggests a frequency metric to determine output (e.g. viewers consume content 5 times per week, guests 10 times per week)
 4. To get the metric, need the total page views, then proportion of viewer and guest to total of those users who were downgraded from editor
 ---------------------------------------------------------------------------------------------------------------------*/

-- create a new view for simplicity with the deletions already omitted (e.g. deleted user won't access content)
create or replace view dm_editor_downgrades_excl_deletions as
(
select  wm.workspace_id                                                 as workspace_id,
        wm.user_id                                                      as user_id,
        trunc(added)                                                    as member_added_to_workspace_date,
        trunc(deleted)                                                  as member_deleted_from_workspace_date,
        case when wm.editor = True  then 1 else 0 end                   as editor_flag,
        case when wm.guest = True   then 1 else 0 end                   as guest_flag,
        case when (wm.editor = False and wm.guest = False) then 1 end   as viewer_flag,
        case when wm.deleted is not null then 1 end                     as deleted_flag,
        ed.max                                                          as event_date
from    dev.public.clo_workspace_member wm
join    dev.public.dm_editor_downgrades ed on wm.user_id = ed.user_id
join    dev.public.dm_paid_customers_subscriptions_workspaces pcsw on wm.workspace_id = pcsw.workspace_id
and     wm.editor != True
and     wm.deleted is null
) with no schema binding;

-- need the user_id and max event created date for the deletion, then want to count page views after the status change date, group by viewer/guest

select  count(eded.user_id),
        trunc(eded.event_date),
        eded.guest_flag,
        eded.viewer_flag,
        date_part('mon', ute.created) as page_view_month
from    dm_editor_downgrades_excl_deletions eded
join    clo_user_track_event ute on eded.user_id = ute.user_id
where   ute.event = 'view-page'
and     ute.created >= '02/11/2022'
and     ute.created > eded.event_date
group by 2, 3, 4, 5;

-- also need total page views for each month to get proportions, just limit on paid customers
select  count(user_id),
        date_part('mon', created)
from    clo_user_track_event
where   event = 'view-page'
and     created >= '02/11/2022'
and     workspace_id in (select distinct(workspace_id) from dm_paid_customers_subscriptions_workspaces)
group by 2;

-- extract to excel for charting


select  *
from    clo_user_track_event
where   event = 'view-page'
and     created >= '02/11/2022'
limit 100;

select count(*)
from    clo_user_track_event
where event = 'view-page'
and created >= '02/11/2022';
-- 30,179,984


/* ---------------------------------------------------------------------------------------------------------------------
 QUESTION 3
 ----------

 Are editors removed in relatively large blocks (suggesting an active culling effort to reduce costs),
 or one at a time (suggesting regular maintenance)?

 Translated:
 1. Look at editors that were downgraded
 2. calculate the date-diffs
 ---------------------------------------------------------------------------------------------------------------------*/

-- ran out of time




/* ---------------------------------------------------------------------------------------------------------------------
 QUESTION 4
 ----------

 Additional insights into removal trends
 ---------------------------------------------------------------------------------------------------------------------*/

select      m.*,
            s.*
from        dev.public.str_sub_change_m m
join        dev.public.str_sub s on m.id = s.id;

-- quick look at the table
select  *
from    str_sub_change_m
order by    updated_at_m, id;

-- add in +/- flag case statement
select      id                  as subscription_id,
            trunc(updated_at_m) as update_month,
            case
                when quantity_change < 0 then 'Reduction'
                when quantity_change > 0 then 'Addition'
                else 'Zero'
            end as quantity_change_type,
            abs(quantity_change) as quantity_change_abs
from        str_sub_change_m;

-- using above query, don't need sub_id
select      trunc(updated_at_m) as update_month,
            case
                when quantity_change < 0 then 'Reduction'
                when quantity_change > 0 then 'Addition'
                else 'Zero Change'
            end as quantity_change_type,
            abs(quantity_change) as quantity_change_abs
from        str_sub_change_m;
