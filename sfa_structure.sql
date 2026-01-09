--
-- PostgreSQL database dump
--

-- Dumped from database version 10.16 (Ubuntu 10.16-1.pgdg20.04+1)
-- Dumped by pg_dump version 10.16 (Ubuntu 10.16-1.pgdg20.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: hdb_catalog; Type: SCHEMA; Schema: -; Owner: prod_kelava
--

CREATE SCHEMA hdb_catalog;


ALTER SCHEMA hdb_catalog OWNER TO prod_kelava;

--
-- Name: hdb_views; Type: SCHEMA; Schema: -; Owner: prod_kelava
--

CREATE SCHEMA hdb_views;


ALTER SCHEMA hdb_views OWNER TO prod_kelava;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: check_violation(text); Type: FUNCTION; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE FUNCTION hdb_catalog.check_violation(msg text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
  BEGIN
    RAISE check_violation USING message=msg;
  END;
$$;


ALTER FUNCTION hdb_catalog.check_violation(msg text) OWNER TO prod_kelava;

--
-- Name: hdb_schema_update_event_notifier(); Type: FUNCTION; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE FUNCTION hdb_catalog.hdb_schema_update_event_notifier() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
    instance_id uuid;
    occurred_at timestamptz;
    invalidations json;
    curr_rec record;
  BEGIN
    instance_id = NEW.instance_id;
    occurred_at = NEW.occurred_at;
    invalidations = NEW.invalidations;
    PERFORM pg_notify('hasura_schema_update', json_build_object(
      'instance_id', instance_id,
      'occurred_at', occurred_at,
      'invalidations', invalidations
      )::text);
    RETURN curr_rec;
  END;
$$;


ALTER FUNCTION hdb_catalog.hdb_schema_update_event_notifier() OWNER TO prod_kelava;

--
-- Name: inject_table_defaults(text, text, text, text); Type: FUNCTION; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE FUNCTION hdb_catalog.inject_table_defaults(view_schema text, view_name text, tab_schema text, tab_name text) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        r RECORD;
    BEGIN
      FOR r IN SELECT column_name, column_default FROM information_schema.columns WHERE table_schema = tab_schema AND table_name = tab_name AND column_default IS NOT NULL LOOP
          EXECUTE format('ALTER VIEW %I.%I ALTER COLUMN %I SET DEFAULT %s;', view_schema, view_name, r.column_name, r.column_default);
      END LOOP;
    END;
$$;


ALTER FUNCTION hdb_catalog.inject_table_defaults(view_schema text, view_name text, tab_schema text, tab_name text) OWNER TO prod_kelava;

--
-- Name: insert_event_log(text, text, text, text, json); Type: FUNCTION; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE FUNCTION hdb_catalog.insert_event_log(schema_name text, table_name text, trigger_name text, op text, row_data json) RETURNS text
    LANGUAGE plpgsql
    AS $$
  DECLARE
    id text;
    payload json;
    session_variables json;
    server_version_num int;
    trace_context json;
  BEGIN
    id := gen_random_uuid();
    server_version_num := current_setting('server_version_num');
    IF server_version_num >= 90600 THEN
      session_variables := current_setting('hasura.user', 't');
      trace_context := current_setting('hasura.tracecontext', 't');
    ELSE
      BEGIN
        session_variables := current_setting('hasura.user');
      EXCEPTION WHEN OTHERS THEN
                  session_variables := NULL;
      END;
      BEGIN
        trace_context := current_setting('hasura.tracecontext');
      EXCEPTION WHEN OTHERS THEN
        trace_context := NULL;
      END;
    END IF;
    payload := json_build_object(
      'op', op,
      'data', row_data,
      'session_variables', session_variables,
      'trace_context', trace_context
    );
    INSERT INTO hdb_catalog.event_log
                (id, schema_name, table_name, trigger_name, payload)
    VALUES
    (id, schema_name, table_name, trigger_name, payload);
    RETURN id;
  END;
$$;


ALTER FUNCTION hdb_catalog.insert_event_log(schema_name text, table_name text, trigger_name text, op text, row_data json) OWNER TO prod_kelava;

--
-- Name: base36_encode(bigint, integer); Type: FUNCTION; Schema: public; Owner: prod_kelava
--

CREATE FUNCTION public.base36_encode(digits bigint, min_width integer DEFAULT 0) RETURNS character varying
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    chars char[]; 
    ret varchar; 
    val bigint; 
BEGIN
    chars := ARRAY['0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'];
    val := digits; 
    ret := ''; 
    IF val < 0 THEN 
        val := val * -1; 
    END IF; 
    WHILE val != 0 LOOP 
        ret := chars[(val % 36)+1] || ret; 
        val := val / 36; 
    END LOOP;

    IF min_width > 0 AND char_length(ret) < min_width THEN 
        ret := lpad(ret, min_width, '0'); 
    END IF;

    RETURN ret;
END;
$$;


ALTER FUNCTION public.base36_encode(digits bigint, min_width integer) OWNER TO prod_kelava;

--
-- Name: m_client_bi(); Type: FUNCTION; Schema: public; Owner: prod_kelava
--

CREATE FUNCTION public.m_client_bi() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE SO INTEGER;
DECLARE CODE CHAR;
BEGIN
    NEW.code = (select base36_encode(new.id, 3));
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.m_client_bi() OWNER TO prod_kelava;

--
-- Name: m_contract_approval_ai(); Type: FUNCTION; Schema: public; Owner: prod_kelava
--

CREATE FUNCTION public.m_contract_approval_ai() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE TIPE VARCHAR;
DECLARE NEW_ID_CUSTOMER_OUTLET INTEGER;
BEGIN
  IF NEW.status = 'Approved' THEN 
    TIPE = (SELECT t.Tipe FROM m_contract t WHERE id = NEW.id_contract);
    IF TIPE = 'NOO' THEN
      INSERT INTO m_customer_outlet (code, name, address, phone1, fax, contact_person_name, contact_person_phone, id_area, id_country, id_city, id_subarea, id_customer, id_province, created_by, created_date)
        SELECT '' as code,
        trim('"' from cast(meta_data::json->'customer_outlet'->'name' as varchar)) as name,
        trim('"' from cast(meta_data::json->'customer_outlet'->'address' as varchar)) as address,
        trim('"' from cast(meta_data::json->'customer_outlet'->'phone' as varchar)) as phone1,
        trim('"' from cast(meta_data::json->'customer_outlet'->'fax' as varchar)) as fax,
        trim('"' from cast(meta_data::json->'customer_outlet'->'pic' as varchar)) as contact_person_name,
        trim('"' from cast(meta_data::json->'customer_outlet'->'pic_phone' as varchar)) as contact_person_phone,
        cast(meta_data::json->'customer_outlet'->>'id_area' as integer) as id_area,
        cast(meta_data::json->'customer_outlet'->>'id_country' as integer) as id_country,
        cast(meta_data::json->'customer_outlet'->>'id_city' as integer) as id_city,
        cast(meta_data::json->'customer_outlet'->>'id_subarea' as integer) as id_subarea,
        id_customer,
        cast(meta_data::json->'customer_outlet'->>'id_province' as integer) as id_province,
        1 as created_by,
        now() as created_date
        FROM m_contract WHERE id = NEW.id_contract
        RETURNING id INTO NEW_ID_CUSTOMER_OUTLET;
      UPDATE m_contract SET id_customer_outlet = NEW_ID_CUSTOMER_OUTLET WHERE id = NEW.id_contract;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.m_contract_approval_ai() OWNER TO prod_kelava;

--
-- Name: m_contract_au(); Type: FUNCTION; Schema: public; Owner: prod_kelava
--

CREATE FUNCTION public.m_contract_au() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE TIPE VARCHAR;
BEGIN
  IF NEW.status = 'Supplied' THEN 
    INSERT INTO t_hardware_usage (id_contract, id_hardware, created_by, start_date, end_date, created_date, status)
    SELECT 
      id as id_contract, cast(meta_data::json->>'id_hardware' as integer) as id_hardware, COALESCE(updated_by, 4) as created_by, start_date, end_date, now() as created_date, 'Supplied'
    FROM (
      SELECT id, json_array_elements(meta_data) as meta_data, updated_by, start_date, end_date FROM m_contract WHERE id = NEW.id
    ) t;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.m_contract_au() OWNER TO prod_kelava;

--
-- Name: m_contract_bi(); Type: FUNCTION; Schema: public; Owner: prod_kelava
--

CREATE FUNCTION public.m_contract_bi() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE CONTRACTNUMBER INTEGER;
BEGIN
    IF NEW.tipe::text = 'Supporting Hardware' THEN
        CONTRACTNUMBER = (SELECT SUBSTRING(MAX(contract_number), 12, 15) FROM m_contract WHERE TO_CHAR(created_date, 'YYYY-MM-DD') = TO_CHAR(NOW(), 'YYYY-MM-DD') AND tipe = 'Supporting Hardware');
        CONTRACTNUMBER = COALESCE(CONTRACTNUMBER, 0) + 1;
        NEW.contract_number = 'SH/' || TO_CHAR(NOW(), 'YY') || '/' || TO_CHAR(NOW(), 'MM') || '/' || TO_CHAR(NOW(), 'DD') || LPAD(CAST(CONTRACTNUMBER AS VARCHAR(10)), 4, '0');
    ELSIF NEW.tipe::text = 'NOO' THEN
        CONTRACTNUMBER = (SELECT SUBSTRING(MAX(contract_number), 13, 16) FROM m_contract WHERE TO_CHAR(created_date, 'YYYY-MM-DD') = TO_CHAR(NOW(), 'YYYY-MM-DD') AND tipe = 'NOO');
        CONTRACTNUMBER = COALESCE(CONTRACTNUMBER, 0) + 1;
        NEW.contract_number = 'NOO/' || TO_CHAR(NOW(), 'YY') || '/' || TO_CHAR(NOW(), 'MM') || '/' || TO_CHAR(NOW(), 'DD') || LPAD(CAST(CONTRACTNUMBER AS VARCHAR(10)), 4, '0');
    ELSIF NEW.tipe::text = 'Kemitraan' THEN
        CONTRACTNUMBER = (SELECT SUBSTRING(MAX(contract_number), 14, 17) FROM m_contract WHERE TO_CHAR(created_date, 'YYYY-MM-DD') = TO_CHAR(NOW(), 'YYYY-MM-DD') AND tipe = 'Kemitraan');
        CONTRACTNUMBER = COALESCE(CONTRACTNUMBER, 0) + 1;
        NEW.contract_number = 'KMTR/' || TO_CHAR(NOW(), 'YY') || '/' || TO_CHAR(NOW(), 'MM') || '/' || TO_CHAR(NOW(), 'DD') || LPAD(CAST(CONTRACTNUMBER AS VARCHAR(10)), 4, '0');
    ELSIF NEW.tipe::text = 'TOP' THEN
        CONTRACTNUMBER = (SELECT SUBSTRING(MAX(contract_number), 13, 16) FROM m_contract WHERE TO_CHAR(created_date, 'YYYY-MM-DD') = TO_CHAR(NOW(), 'YYYY-MM-DD') AND tipe = 'TOP');
        CONTRACTNUMBER = COALESCE(CONTRACTNUMBER, 0) + 1;
        NEW.contract_number = 'TOP/' || TO_CHAR(NOW(), 'YY') || '/' || TO_CHAR(NOW(), 'MM') || '/' || TO_CHAR(NOW(), 'DD') || LPAD(CAST(CONTRACTNUMBER AS VARCHAR(10)), 4, '0');
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.m_contract_bi() OWNER TO prod_kelava;

--
-- Name: m_customer_outlet_bi(); Type: FUNCTION; Schema: public; Owner: prod_kelava
--

CREATE FUNCTION public.m_customer_outlet_bi() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE CODE_OUTLET INTEGER;
BEGIN
    CODE_OUTLET = (SELECT SUBSTRING(MAX(code), 4, 6) FROM m_customer_outlet WHERE code LIKE '%OT%');
    CODE_OUTLET = COALESCE(CODE_OUTLET, 0) + 1;
    NEW.code = 'OT-' || LPAD(CAST(CODE_OUTLET AS VARCHAR(10)), 3, '0');
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.m_customer_outlet_bi() OWNER TO prod_kelava;

--
-- Name: t_sales_order_bi(); Type: FUNCTION; Schema: public; Owner: prod_kelava
--

CREATE FUNCTION public.t_sales_order_bi() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE SO INTEGER;
DECLARE CODE CHAR(256);
BEGIN
    CODE = (select t.code from m_client t where id = NEW.id_client);
    SO = (SELECT max(SUBSTRING(tso.sales_order_number,  length(mc.code)+2)::int)
                FROM t_sales_order tso inner join m_client mc on mc.id = tso.id_client 
                WHERE tso.id_client = NEW.id_client and SUBSTRING(tso.sales_order_number, 0, length(mc.code)+1) = mc.code);
    SO = COALESCE(SO, 0) + 1;
    NEW.sales_order_number = CODE  || '-' || SO;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.t_sales_order_bi() OWNER TO prod_kelava;

--
-- Name: t_withdraw_bi(); Type: FUNCTION; Schema: public; Owner: prod_kelava
--

CREATE FUNCTION public.t_withdraw_bi() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE WITHDRAW INTEGER;
DECLARE CODE CHAR(256);
BEGIN
    CODE = NEW.client_code;
    WITHDRAW = (SELECT max(SUBSTRING(tw.withdraw_no,  length(CODE)+5)::int)
                FROM t_withdraw tw);
    WITHDRAW  = COALESCE(WITHDRAW , 0) + 1;
    NEW.withdraw_no = CODE  || '-WD-' || WITHDRAW;
    RETURN NEW;
END$$;


ALTER FUNCTION public.t_withdraw_bi() OWNER TO prod_kelava;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: event_triggers; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.event_triggers (
    name text NOT NULL,
    type text NOT NULL,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    configuration json,
    comment text
);


ALTER TABLE hdb_catalog.event_triggers OWNER TO prod_kelava;

--
-- Name: hdb_action; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_action (
    action_name text NOT NULL,
    action_defn jsonb NOT NULL,
    comment text,
    is_system_defined boolean DEFAULT false
);


ALTER TABLE hdb_catalog.hdb_action OWNER TO prod_kelava;

--
-- Name: hdb_action_permission; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_action_permission (
    action_name text NOT NULL,
    role_name text NOT NULL,
    definition jsonb DEFAULT '{}'::jsonb NOT NULL,
    comment text
);


ALTER TABLE hdb_catalog.hdb_action_permission OWNER TO prod_kelava;

--
-- Name: hdb_allowlist; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_allowlist (
    collection_name text
);


ALTER TABLE hdb_catalog.hdb_allowlist OWNER TO prod_kelava;

--
-- Name: hdb_check_constraint; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_check_constraint AS
 SELECT (n.nspname)::text AS table_schema,
    (ct.relname)::text AS table_name,
    (r.conname)::text AS constraint_name,
    pg_get_constraintdef(r.oid, true) AS "check"
   FROM ((pg_constraint r
     JOIN pg_class ct ON ((r.conrelid = ct.oid)))
     JOIN pg_namespace n ON ((ct.relnamespace = n.oid)))
  WHERE (r.contype = 'c'::"char");


ALTER TABLE hdb_catalog.hdb_check_constraint OWNER TO prod_kelava;

--
-- Name: hdb_computed_field; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_computed_field (
    table_schema text NOT NULL,
    table_name text NOT NULL,
    computed_field_name text NOT NULL,
    definition jsonb NOT NULL,
    comment text
);


ALTER TABLE hdb_catalog.hdb_computed_field OWNER TO prod_kelava;

--
-- Name: hdb_computed_field_function; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_computed_field_function AS
 SELECT hdb_computed_field.table_schema,
    hdb_computed_field.table_name,
    hdb_computed_field.computed_field_name,
        CASE
            WHEN (((hdb_computed_field.definition -> 'function'::text) ->> 'name'::text) IS NULL) THEN (hdb_computed_field.definition ->> 'function'::text)
            ELSE ((hdb_computed_field.definition -> 'function'::text) ->> 'name'::text)
        END AS function_name,
        CASE
            WHEN (((hdb_computed_field.definition -> 'function'::text) ->> 'schema'::text) IS NULL) THEN 'public'::text
            ELSE ((hdb_computed_field.definition -> 'function'::text) ->> 'schema'::text)
        END AS function_schema
   FROM hdb_catalog.hdb_computed_field;


ALTER TABLE hdb_catalog.hdb_computed_field_function OWNER TO prod_kelava;

--
-- Name: hdb_cron_triggers; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_cron_triggers (
    name text NOT NULL,
    webhook_conf json NOT NULL,
    cron_schedule text NOT NULL,
    payload json,
    retry_conf json,
    header_conf json,
    include_in_metadata boolean DEFAULT false NOT NULL,
    comment text
);


ALTER TABLE hdb_catalog.hdb_cron_triggers OWNER TO prod_kelava;

--
-- Name: hdb_custom_types; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_custom_types (
    custom_types jsonb NOT NULL
);


ALTER TABLE hdb_catalog.hdb_custom_types OWNER TO prod_kelava;

--
-- Name: hdb_foreign_key_constraint; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_foreign_key_constraint AS
 SELECT (q.table_schema)::text AS table_schema,
    (q.table_name)::text AS table_name,
    (q.constraint_name)::text AS constraint_name,
    (min(q.constraint_oid))::integer AS constraint_oid,
    min((q.ref_table_table_schema)::text) AS ref_table_table_schema,
    min((q.ref_table)::text) AS ref_table,
    json_object_agg(ac.attname, afc.attname) AS column_mapping,
    min((q.confupdtype)::text) AS on_update,
    min((q.confdeltype)::text) AS on_delete,
    json_agg(ac.attname) AS columns,
    json_agg(afc.attname) AS ref_columns
   FROM ((( SELECT ctn.nspname AS table_schema,
            ct.relname AS table_name,
            r.conrelid AS table_id,
            r.conname AS constraint_name,
            r.oid AS constraint_oid,
            cftn.nspname AS ref_table_table_schema,
            cft.relname AS ref_table,
            r.confrelid AS ref_table_id,
            r.confupdtype,
            r.confdeltype,
            unnest(r.conkey) AS column_id,
            unnest(r.confkey) AS ref_column_id
           FROM ((((pg_constraint r
             JOIN pg_class ct ON ((r.conrelid = ct.oid)))
             JOIN pg_namespace ctn ON ((ct.relnamespace = ctn.oid)))
             JOIN pg_class cft ON ((r.confrelid = cft.oid)))
             JOIN pg_namespace cftn ON ((cft.relnamespace = cftn.oid)))
          WHERE (r.contype = 'f'::"char")) q
     JOIN pg_attribute ac ON (((q.column_id = ac.attnum) AND (q.table_id = ac.attrelid))))
     JOIN pg_attribute afc ON (((q.ref_column_id = afc.attnum) AND (q.ref_table_id = afc.attrelid))))
  GROUP BY q.table_schema, q.table_name, q.constraint_name;


ALTER TABLE hdb_catalog.hdb_foreign_key_constraint OWNER TO prod_kelava;

--
-- Name: hdb_function; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_function (
    function_schema text NOT NULL,
    function_name text NOT NULL,
    configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_system_defined boolean DEFAULT false
);


ALTER TABLE hdb_catalog.hdb_function OWNER TO prod_kelava;

--
-- Name: hdb_function_agg; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_function_agg AS
 SELECT (p.proname)::text AS function_name,
    (pn.nspname)::text AS function_schema,
    pd.description,
        CASE
            WHEN (p.provariadic = (0)::oid) THEN false
            ELSE true
        END AS has_variadic,
        CASE
            WHEN ((p.provolatile)::text = ('i'::character(1))::text) THEN 'IMMUTABLE'::text
            WHEN ((p.provolatile)::text = ('s'::character(1))::text) THEN 'STABLE'::text
            WHEN ((p.provolatile)::text = ('v'::character(1))::text) THEN 'VOLATILE'::text
            ELSE NULL::text
        END AS function_type,
    pg_get_functiondef(p.oid) AS function_definition,
    (rtn.nspname)::text AS return_type_schema,
    (rt.typname)::text AS return_type_name,
    (rt.typtype)::text AS return_type_type,
    p.proretset AS returns_set,
    ( SELECT COALESCE(json_agg(json_build_object('schema', q.schema, 'name', q.name, 'type', q.type)), '[]'::json) AS "coalesce"
           FROM ( SELECT pt.typname AS name,
                    pns.nspname AS schema,
                    pt.typtype AS type,
                    pat.ordinality
                   FROM ((unnest(COALESCE(p.proallargtypes, (p.proargtypes)::oid[])) WITH ORDINALITY pat(oid, ordinality)
                     LEFT JOIN pg_type pt ON ((pt.oid = pat.oid)))
                     LEFT JOIN pg_namespace pns ON ((pt.typnamespace = pns.oid)))
                  ORDER BY pat.ordinality) q) AS input_arg_types,
    to_json(COALESCE(p.proargnames, ARRAY[]::text[])) AS input_arg_names,
    p.pronargdefaults AS default_args,
    (p.oid)::integer AS function_oid
   FROM ((((pg_proc p
     JOIN pg_namespace pn ON ((pn.oid = p.pronamespace)))
     JOIN pg_type rt ON ((rt.oid = p.prorettype)))
     JOIN pg_namespace rtn ON ((rtn.oid = rt.typnamespace)))
     LEFT JOIN pg_description pd ON ((p.oid = pd.objoid)))
  WHERE (((pn.nspname)::text !~~ 'pg_%'::text) AND ((pn.nspname)::text <> ALL (ARRAY['information_schema'::text, 'hdb_catalog'::text, 'hdb_views'::text])) AND (NOT (EXISTS ( SELECT 1
           FROM pg_aggregate
          WHERE ((pg_aggregate.aggfnoid)::oid = p.oid)))));


ALTER TABLE hdb_catalog.hdb_function_agg OWNER TO prod_kelava;

--
-- Name: hdb_function_info_agg; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_function_info_agg AS
 SELECT hdb_function_agg.function_name,
    hdb_function_agg.function_schema,
    row_to_json(( SELECT e.*::record AS e
           FROM ( SELECT hdb_function_agg.description,
                    hdb_function_agg.has_variadic,
                    hdb_function_agg.function_type,
                    hdb_function_agg.return_type_schema,
                    hdb_function_agg.return_type_name,
                    hdb_function_agg.return_type_type,
                    hdb_function_agg.returns_set,
                    hdb_function_agg.input_arg_types,
                    hdb_function_agg.input_arg_names,
                    hdb_function_agg.default_args,
                    (EXISTS ( SELECT 1
                           FROM information_schema.tables
                          WHERE (((tables.table_schema)::text = hdb_function_agg.return_type_schema) AND ((tables.table_name)::text = hdb_function_agg.return_type_name)))) AS returns_table) e)) AS function_info
   FROM hdb_catalog.hdb_function_agg;


ALTER TABLE hdb_catalog.hdb_function_info_agg OWNER TO prod_kelava;

--
-- Name: hdb_permission; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_permission (
    table_schema name NOT NULL,
    table_name name NOT NULL,
    role_name text NOT NULL,
    perm_type text NOT NULL,
    perm_def jsonb NOT NULL,
    comment text,
    is_system_defined boolean DEFAULT false,
    CONSTRAINT hdb_permission_perm_type_check CHECK ((perm_type = ANY (ARRAY['insert'::text, 'select'::text, 'update'::text, 'delete'::text])))
);


ALTER TABLE hdb_catalog.hdb_permission OWNER TO prod_kelava;

--
-- Name: hdb_permission_agg; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_permission_agg AS
 SELECT hdb_permission.table_schema,
    hdb_permission.table_name,
    hdb_permission.role_name,
    json_object_agg(hdb_permission.perm_type, hdb_permission.perm_def) AS permissions
   FROM hdb_catalog.hdb_permission
  GROUP BY hdb_permission.table_schema, hdb_permission.table_name, hdb_permission.role_name;


ALTER TABLE hdb_catalog.hdb_permission_agg OWNER TO prod_kelava;

--
-- Name: hdb_primary_key; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_primary_key AS
 SELECT tc.table_schema,
    tc.table_name,
    tc.constraint_name,
    json_agg(constraint_column_usage.column_name) AS columns
   FROM (information_schema.table_constraints tc
     JOIN ( SELECT x.tblschema AS table_schema,
            x.tblname AS table_name,
            x.colname AS column_name,
            x.cstrname AS constraint_name
           FROM ( SELECT DISTINCT nr.nspname,
                    r.relname,
                    a.attname,
                    c.conname
                   FROM pg_namespace nr,
                    pg_class r,
                    pg_attribute a,
                    pg_depend d,
                    pg_namespace nc,
                    pg_constraint c
                  WHERE ((nr.oid = r.relnamespace) AND (r.oid = a.attrelid) AND (d.refclassid = ('pg_class'::regclass)::oid) AND (d.refobjid = r.oid) AND (d.refobjsubid = a.attnum) AND (d.classid = ('pg_constraint'::regclass)::oid) AND (d.objid = c.oid) AND (c.connamespace = nc.oid) AND (c.contype = 'c'::"char") AND (r.relkind = ANY (ARRAY['r'::"char", 'p'::"char"])) AND (NOT a.attisdropped))
                UNION ALL
                 SELECT nr.nspname,
                    r.relname,
                    a.attname,
                    c.conname
                   FROM pg_namespace nr,
                    pg_class r,
                    pg_attribute a,
                    pg_namespace nc,
                    pg_constraint c
                  WHERE ((nr.oid = r.relnamespace) AND (r.oid = a.attrelid) AND (nc.oid = c.connamespace) AND (r.oid =
                        CASE c.contype
                            WHEN 'f'::"char" THEN c.confrelid
                            ELSE c.conrelid
                        END) AND (a.attnum = ANY (
                        CASE c.contype
                            WHEN 'f'::"char" THEN c.confkey
                            ELSE c.conkey
                        END)) AND (NOT a.attisdropped) AND (c.contype = ANY (ARRAY['p'::"char", 'u'::"char", 'f'::"char"])) AND (r.relkind = ANY (ARRAY['r'::"char", 'p'::"char"])))) x(tblschema, tblname, colname, cstrname)) constraint_column_usage ON ((((tc.constraint_name)::text = (constraint_column_usage.constraint_name)::text) AND ((tc.table_schema)::text = (constraint_column_usage.table_schema)::text) AND ((tc.table_name)::text = (constraint_column_usage.table_name)::text))))
  WHERE ((tc.constraint_type)::text = 'PRIMARY KEY'::text)
  GROUP BY tc.table_schema, tc.table_name, tc.constraint_name;


ALTER TABLE hdb_catalog.hdb_primary_key OWNER TO prod_kelava;

--
-- Name: hdb_query_collection; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_query_collection (
    collection_name text NOT NULL,
    collection_defn jsonb NOT NULL,
    comment text,
    is_system_defined boolean DEFAULT false
);


ALTER TABLE hdb_catalog.hdb_query_collection OWNER TO prod_kelava;

--
-- Name: hdb_relationship; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_relationship (
    table_schema name NOT NULL,
    table_name name NOT NULL,
    rel_name text NOT NULL,
    rel_type text,
    rel_def jsonb NOT NULL,
    comment text,
    is_system_defined boolean DEFAULT false,
    CONSTRAINT hdb_relationship_rel_type_check CHECK ((rel_type = ANY (ARRAY['object'::text, 'array'::text])))
);


ALTER TABLE hdb_catalog.hdb_relationship OWNER TO prod_kelava;

--
-- Name: hdb_remote_relationship; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_remote_relationship (
    remote_relationship_name text NOT NULL,
    table_schema name NOT NULL,
    table_name name NOT NULL,
    definition jsonb NOT NULL
);


ALTER TABLE hdb_catalog.hdb_remote_relationship OWNER TO prod_kelava;

--
-- Name: hdb_role; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_role AS
 SELECT DISTINCT q.role_name
   FROM ( SELECT hdb_permission.role_name
           FROM hdb_catalog.hdb_permission
        UNION ALL
         SELECT hdb_action_permission.role_name
           FROM hdb_catalog.hdb_action_permission) q;


ALTER TABLE hdb_catalog.hdb_role OWNER TO prod_kelava;

--
-- Name: hdb_schema_update_event; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_schema_update_event (
    instance_id uuid NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    invalidations json NOT NULL
);


ALTER TABLE hdb_catalog.hdb_schema_update_event OWNER TO prod_kelava;

--
-- Name: hdb_table; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.hdb_table (
    table_schema name NOT NULL,
    table_name name NOT NULL,
    configuration jsonb,
    is_system_defined boolean DEFAULT false,
    is_enum boolean DEFAULT false NOT NULL
);


ALTER TABLE hdb_catalog.hdb_table OWNER TO prod_kelava;

--
-- Name: hdb_table_info_agg; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_table_info_agg AS
 SELECT schema.nspname AS table_schema,
    "table".relname AS table_name,
    jsonb_build_object('oid', ("table".oid)::integer, 'columns', COALESCE(columns.info, '[]'::jsonb), 'primary_key', primary_key.info, 'unique_constraints', COALESCE(unique_constraints.info, '[]'::jsonb), 'foreign_keys', COALESCE(foreign_key_constraints.info, '[]'::jsonb), 'view_info',
        CASE "table".relkind
            WHEN 'v'::"char" THEN jsonb_build_object('is_updatable', ((pg_relation_is_updatable(("table".oid)::regclass, true) & 4) = 4), 'is_insertable', ((pg_relation_is_updatable(("table".oid)::regclass, true) & 8) = 8), 'is_deletable', ((pg_relation_is_updatable(("table".oid)::regclass, true) & 16) = 16))
            ELSE NULL::jsonb
        END, 'description', description.description) AS info,
    jsonb_build_object('oid', ("table".oid)::integer, 'columns', COALESCE(columns.info, '[]'::jsonb), 'primary_key', primary_key.info, 'unique_constraints', COALESCE(unique_constraints.info, '[]'::jsonb), 'foreign_keys', COALESCE(foreign_key_constraints.info, '[]'::jsonb), 'view_info',
        CASE "table".relkind
            WHEN 'v'::"char" THEN jsonb_build_object('is_updatable', ((pg_relation_is_updatable(("table".oid)::regclass, true) & 4) = 4), 'is_insertable', ((pg_relation_is_updatable(("table".oid)::regclass, true) & 8) = 8), 'is_deletable', ((pg_relation_is_updatable(("table".oid)::regclass, true) & 16) = 16))
            ELSE NULL::jsonb
        END, 'description', description.description) AS description,
    COALESCE(columns.info, '[]'::jsonb) AS columns
   FROM ((((((pg_class "table"
     JOIN pg_namespace schema ON ((schema.oid = "table".relnamespace)))
     LEFT JOIN pg_description description ON (((description.classoid = ('pg_class'::regclass)::oid) AND (description.objoid = "table".oid) AND (description.objsubid = 0))))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('name', "column".attname, 'position', "column".attnum, 'type', COALESCE(base_type.typname, type.typname), 'is_nullable', (NOT "column".attnotnull), 'description', col_description("table".oid, ("column".attnum)::integer))) AS info
           FROM ((pg_attribute "column"
             LEFT JOIN pg_type type ON ((type.oid = "column".atttypid)))
             LEFT JOIN pg_type base_type ON (((type.typtype = 'd'::"char") AND (base_type.oid = type.typbasetype))))
          WHERE (("column".attrelid = "table".oid) AND ("column".attnum > 0) AND (NOT "column".attisdropped))) columns ON (true))
     LEFT JOIN LATERAL ( SELECT jsonb_build_object('constraint', jsonb_build_object('name', class.relname, 'oid', (class.oid)::integer), 'columns', COALESCE(columns_1.info, '[]'::jsonb)) AS info
           FROM ((pg_index index
             JOIN pg_class class ON ((class.oid = index.indexrelid)))
             LEFT JOIN LATERAL ( SELECT jsonb_agg("column".attname) AS info
                   FROM pg_attribute "column"
                  WHERE (("column".attrelid = "table".oid) AND ("column".attnum = ANY ((index.indkey)::smallint[])))) columns_1 ON (true))
          WHERE ((index.indrelid = "table".oid) AND index.indisprimary)) primary_key ON (true))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('name', class.relname, 'oid', (class.oid)::integer)) AS info
           FROM (pg_index index
             JOIN pg_class class ON ((class.oid = index.indexrelid)))
          WHERE ((index.indrelid = "table".oid) AND index.indisunique AND (NOT index.indisprimary))) unique_constraints ON (true))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('constraint', jsonb_build_object('name', foreign_key.constraint_name, 'oid', foreign_key.constraint_oid), 'columns', foreign_key.columns, 'foreign_table', jsonb_build_object('schema', foreign_key.ref_table_table_schema, 'name', foreign_key.ref_table), 'foreign_columns', foreign_key.ref_columns)) AS info
           FROM hdb_catalog.hdb_foreign_key_constraint foreign_key
          WHERE ((foreign_key.table_schema = (schema.nspname)::text) AND (foreign_key.table_name = ("table".relname)::text))) foreign_key_constraints ON (true))
  WHERE ("table".relkind = ANY (ARRAY['r'::"char", 't'::"char", 'v'::"char", 'm'::"char", 'f'::"char", 'p'::"char"]));


ALTER TABLE hdb_catalog.hdb_table_info_agg OWNER TO prod_kelava;

--
-- Name: hdb_unique_constraint; Type: VIEW; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE VIEW hdb_catalog.hdb_unique_constraint AS
 SELECT tc.table_name,
    tc.constraint_schema AS table_schema,
    tc.constraint_name,
    json_agg(kcu.column_name) AS columns
   FROM (information_schema.table_constraints tc
     JOIN information_schema.key_column_usage kcu USING (constraint_schema, constraint_name))
  WHERE ((tc.constraint_type)::text = 'UNIQUE'::text)
  GROUP BY tc.table_name, tc.constraint_schema, tc.constraint_name;


ALTER TABLE hdb_catalog.hdb_unique_constraint OWNER TO prod_kelava;

--
-- Name: remote_schemas; Type: TABLE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TABLE hdb_catalog.remote_schemas (
    id bigint NOT NULL,
    name text,
    definition json,
    comment text
);


ALTER TABLE hdb_catalog.remote_schemas OWNER TO prod_kelava;

--
-- Name: remote_schemas_id_seq; Type: SEQUENCE; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE SEQUENCE hdb_catalog.remote_schemas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE hdb_catalog.remote_schemas_id_seq OWNER TO prod_kelava;

--
-- Name: remote_schemas_id_seq; Type: SEQUENCE OWNED BY; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER SEQUENCE hdb_catalog.remote_schemas_id_seq OWNED BY hdb_catalog.remote_schemas.id;


--
-- Name: bulan_indo; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.bulan_indo (
    bulan character varying NOT NULL,
    seq smallint
);


ALTER TABLE public.bulan_indo OWNER TO prod_kelava;

--
-- Name: event_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.event_id_seq OWNER TO prod_kelava;

--
-- Name: ft_sales_by_product; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.ft_sales_by_product (
    id_product integer NOT NULL,
    total numeric NOT NULL
);


ALTER TABLE public.ft_sales_by_product OWNER TO prod_kelava;

--
-- Name: i_withdraw; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.i_withdraw (
    id integer NOT NULL,
    client_code character varying(256) NOT NULL,
    withdraw_date date NOT NULL,
    amount numeric NOT NULL,
    sync_date timestamp with time zone NOT NULL,
    status character varying(256) NOT NULL,
    image_url text,
    updated_by character varying(256),
    updated_date timestamp with time zone,
    created_by_name character varying(256) NOT NULL,
    withdraw_no character varying(256) NOT NULL,
    remarks text
);


ALTER TABLE public.i_withdraw OWNER TO prod_kelava;

--
-- Name: i_withdraw_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.i_withdraw_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.i_withdraw_id_seq OWNER TO prod_kelava;

--
-- Name: i_withdraw_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.i_withdraw_id_seq OWNED BY public.i_withdraw.id;


--
-- Name: i_withdraw_line; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.i_withdraw_line (
    id integer NOT NULL,
    id_withdraw integer NOT NULL,
    sales_order_number character varying(256) NOT NULL,
    amount numeric NOT NULL
);


ALTER TABLE public.i_withdraw_line OWNER TO prod_kelava;

--
-- Name: i_withdraw_line_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.i_withdraw_line_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.i_withdraw_line_id_seq OWNER TO prod_kelava;

--
-- Name: i_withdraw_line_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.i_withdraw_line_id_seq OWNED BY public.i_withdraw_line.id;


--
-- Name: m_add_on; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_add_on (
    id integer NOT NULL,
    name character varying(256) NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    url text NOT NULL,
    icon character varying(256),
    title character varying(256),
    is_new_tab smallint DEFAULT '0'::smallint NOT NULL
);


ALTER TABLE public.m_add_on OWNER TO prod_kelava;

--
-- Name: m_add_on_client; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_add_on_client (
    id integer NOT NULL,
    id_add_on integer NOT NULL,
    id_client integer NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone NOT NULL,
    created_date timestamp with time zone NOT NULL,
    updated_date timestamp with time zone
);


ALTER TABLE public.m_add_on_client OWNER TO prod_kelava;

--
-- Name: m_add_on_client_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_add_on_client_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_add_on_client_id_seq OWNER TO prod_kelava;

--
-- Name: m_add_on_client_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_add_on_client_id_seq OWNED BY public.m_add_on_client.id;


--
-- Name: m_add_on_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_add_on_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_add_on_id_seq OWNER TO prod_kelava;

--
-- Name: m_add_on_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_add_on_id_seq OWNED BY public.m_add_on.id;


--
-- Name: m_area_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_area_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_area_id_seq OWNER TO prod_kelava;

--
-- Name: m_area; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_area (
    id integer DEFAULT nextval('public.m_area_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_area OWNER TO prod_kelava;

--
-- Name: m_channel_pembayaran; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_channel_pembayaran (
    id integer NOT NULL,
    id_client integer NOT NULL,
    img_url character varying(256),
    name character varying(256) NOT NULL
);


ALTER TABLE public.m_channel_pembayaran OWNER TO prod_kelava;

--
-- Name: m_channel_pembayaran_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_channel_pembayaran_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_channel_pembayaran_id_seq OWNER TO prod_kelava;

--
-- Name: m_channel_pembayaran_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_channel_pembayaran_id_seq OWNED BY public.m_channel_pembayaran.id;


--
-- Name: m_charges; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.m_charges (
    id integer NOT NULL,
    name character varying(256) NOT NULL
);


ALTER TABLE public.m_charges OWNER TO postgres;

--
-- Name: m_charges_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.m_charges_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_charges_id_seq OWNER TO postgres;

--
-- Name: m_charges_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.m_charges_id_seq OWNED BY public.m_charges.id;


--
-- Name: m_city_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_city_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_city_id_seq OWNER TO prod_kelava;

--
-- Name: m_city; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_city (
    id integer DEFAULT nextval('public.m_city_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    id_province integer NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_city OWNER TO prod_kelava;

--
-- Name: m_client; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_client (
    id integer NOT NULL,
    client_name character varying(256) NOT NULL,
    created_date timestamp with time zone DEFAULT now() NOT NULL,
    email character varying(256) NOT NULL,
    pic_name character varying(256) NOT NULL,
    phone character varying(13) NOT NULL,
    npwp character varying(256),
    active_package integer DEFAULT 1 NOT NULL,
    package_exp date NOT NULL,
    code character varying(256),
    callback_url text,
    bank_name character varying(256),
    bank_account_name character varying(256),
    bank_account_no character varying(256),
    invoice_add_text text,
    logo_url character varying(256)
);


ALTER TABLE public.m_client OWNER TO prod_kelava;

--
-- Name: m_client_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_client_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_client_id_seq OWNER TO prod_kelava;

--
-- Name: m_client_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_client_id_seq OWNED BY public.m_client.id;


--
-- Name: m_client_packages; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_client_packages (
    id integer NOT NULL,
    m_client integer NOT NULL,
    m_package integer NOT NULL,
    valid_from date NOT NULL,
    valid_to date NOT NULL
);


ALTER TABLE public.m_client_packages OWNER TO prod_kelava;

--
-- Name: m_client_packages_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_client_packages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_client_packages_id_seq OWNER TO prod_kelava;

--
-- Name: m_client_packages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_client_packages_id_seq OWNED BY public.m_client_packages.id;


--
-- Name: m_client_payment; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_client_payment (
    id integer NOT NULL,
    id_client integer NOT NULL,
    token text NOT NULL
);


ALTER TABLE public.m_client_payment OWNER TO prod_kelava;

--
-- Name: m_client_payment_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_client_payment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_client_payment_id_seq OWNER TO prod_kelava;

--
-- Name: m_client_payment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_client_payment_id_seq OWNED BY public.m_client_payment.id;


--
-- Name: m_contact; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_contact (
    id integer NOT NULL,
    name character varying(256) NOT NULL,
    email text,
    phone1 character varying(20),
    phone2 character varying(20),
    phone3 character varying(20),
    created_by integer,
    created_date timestamp without time zone DEFAULT now(),
    id_client integer,
    updated_by integer,
    updated_date timestamp with time zone,
    id_customer integer,
    id_contact_type integer,
    "position" character varying(256)
);


ALTER TABLE public.m_contact OWNER TO prod_kelava;

--
-- Name: m_contract_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_contract_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_contract_id_seq OWNER TO prod_kelava;

--
-- Name: m_contract; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_contract (
    id integer DEFAULT nextval('public.m_contract_id_seq'::regclass) NOT NULL,
    contract_number character varying,
    tipe character varying(256) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status character varying,
    content text NOT NULL,
    meta_data json NOT NULL,
    remarks character varying(256),
    created_by integer NOT NULL,
    id_customer_outlet integer,
    id_customer integer,
    created_date timestamp with time zone DEFAULT (now() + '00:00:00'::interval) NOT NULL,
    updated_by integer,
    updated_date timestamp with time zone,
    tipe_pelanggan character varying
);


ALTER TABLE public.m_contract OWNER TO prod_kelava;

--
-- Name: COLUMN m_contract.status; Type: COMMENT; Schema: public; Owner: prod_kelava
--

COMMENT ON COLUMN public.m_contract.status IS 'Pending,Done';


--
-- Name: m_contract_approval_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_contract_approval_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_contract_approval_id_seq OWNER TO prod_kelava;

--
-- Name: m_contract_approval; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_contract_approval (
    id integer DEFAULT nextval('public.m_contract_approval_id_seq'::regclass) NOT NULL,
    id_contract integer NOT NULL,
    id_approver integer NOT NULL,
    approval_date timestamp with time zone NOT NULL,
    status character varying NOT NULL,
    remarks character varying(256)
);


ALTER TABLE public.m_contract_approval OWNER TO prod_kelava;

--
-- Name: COLUMN m_contract_approval.status; Type: COMMENT; Schema: public; Owner: prod_kelava
--

COMMENT ON COLUMN public.m_contract_approval.status IS 'Approved,Pending,Rejected';


--
-- Name: m_contract_price_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_contract_price_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_contract_price_id_seq OWNER TO prod_kelava;

--
-- Name: m_contract_price; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_contract_price (
    id integer DEFAULT nextval('public.m_contract_price_id_seq'::regclass) NOT NULL,
    id_product integer NOT NULL,
    id_contract integer NOT NULL,
    price numeric NOT NULL,
    unit character varying(256) NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp without time zone NOT NULL
);


ALTER TABLE public.m_contract_price OWNER TO prod_kelava;

--
-- Name: m_country_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_country_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_country_id_seq OWNER TO prod_kelava;

--
-- Name: m_country; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_country (
    id integer DEFAULT nextval('public.m_country_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_country OWNER TO prod_kelava;

--
-- Name: m_customer_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_customer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_customer_id_seq OWNER TO prod_kelava;

--
-- Name: m_customer; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_customer (
    id integer DEFAULT nextval('public.m_customer_id_seq'::regclass) NOT NULL,
    code character varying(256),
    name character varying(256) NOT NULL,
    address character varying(256),
    phone1 character varying(256),
    phone2 character varying(256),
    fax character varying(256),
    credit_limit numeric DEFAULT '0'::numeric,
    contact_person_name character varying(256),
    contact_person_phone character varying(256),
    npwp character varying(256),
    tax_address character varying(256),
    status character varying(256) NOT NULL,
    payment_term integer DEFAULT 0,
    id_segment integer,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT (now() + '00:00:00'::interval) NOT NULL,
    identity character varying,
    id_client integer NOT NULL,
    email character varying(256),
    is_customer smallint,
    is_vendor smallint,
    new_city character varying(256),
    new_province character varying(256),
    new_country character varying(256),
    user_token character varying(256) NOT NULL,
    password character varying(256),
    username character varying(256),
    token character varying(256),
    is_one_time smallint DEFAULT '0'::smallint NOT NULL,
    foto character varying(256),
    id_customer_group integer,
    born_date date,
    gender character varying(256)
);


ALTER TABLE public.m_customer OWNER TO prod_kelava;

--
-- Name: m_customer_contact; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_customer_contact (
    id integer NOT NULL,
    id_contact integer NOT NULL,
    id_customer integer NOT NULL,
    "position" character varying(256)
);


ALTER TABLE public.m_customer_contact OWNER TO prod_kelava;

--
-- Name: m_customer_contact_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_customer_contact_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_customer_contact_id_seq OWNER TO prod_kelava;

--
-- Name: m_customer_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_customer_contact_id_seq OWNED BY public.m_contact.id;


--
-- Name: m_customer_contact_id_seq1; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_customer_contact_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_customer_contact_id_seq1 OWNER TO prod_kelava;

--
-- Name: m_customer_contact_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_customer_contact_id_seq1 OWNED BY public.m_customer_contact.id;


--
-- Name: m_customer_devices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.m_customer_devices (
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    device_info json,
    device_token character varying(256) NOT NULL,
    id integer NOT NULL,
    id_customer integer NOT NULL
);


ALTER TABLE public.m_customer_devices OWNER TO postgres;

--
-- Name: m_customer_devices_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.m_customer_devices_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_customer_devices_id_seq OWNER TO postgres;

--
-- Name: m_customer_devices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.m_customer_devices_id_seq OWNED BY public.m_customer_devices.id;


--
-- Name: m_customer_group; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.m_customer_group (
    id integer NOT NULL,
    id_client integer NOT NULL,
    name character varying(256) NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL
);


ALTER TABLE public.m_customer_group OWNER TO postgres;

--
-- Name: m_customer_outlet_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_customer_outlet_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_customer_outlet_id_seq OWNER TO prod_kelava;

--
-- Name: m_customer_outlet; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_customer_outlet (
    id integer DEFAULT nextval('public.m_customer_outlet_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    address character varying(256) NOT NULL,
    phone1 character varying(256) NOT NULL,
    phone2 character varying(256),
    fax character varying(256),
    contact_person_name character varying(256),
    contact_person_phone character varying(256),
    id_contract integer,
    id_area integer,
    id_country integer NOT NULL,
    id_city integer NOT NULL,
    id_subarea integer,
    id_customer integer NOT NULL,
    id_province integer NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    key character varying(256),
    id_client integer NOT NULL,
    email character varying(256)
);


ALTER TABLE public.m_customer_outlet OWNER TO prod_kelava;

--
-- Name: m_customer_segment_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_customer_segment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_customer_segment_id_seq OWNER TO prod_kelava;

--
-- Name: m_customer_segment; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_customer_segment (
    id integer DEFAULT nextval('public.m_customer_segment_id_seq'::regclass) NOT NULL,
    name character varying(256) NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_customer_segment OWNER TO prod_kelava;

--
-- Name: m_customer_social_media; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_customer_social_media (
    created_time timestamp without time zone NOT NULL,
    id integer NOT NULL,
    id_customer integer NOT NULL,
    id_sosmed integer NOT NULL,
    profile_id character varying(256) NOT NULL
);


ALTER TABLE public.m_customer_social_media OWNER TO prod_kelava;

--
-- Name: m_customer_social_media_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_customer_social_media_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_customer_social_media_id_seq OWNER TO prod_kelava;

--
-- Name: m_customer_social_media_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_customer_social_media_id_seq OWNED BY public.m_customer_social_media.id;


--
-- Name: m_visit_field1; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_visit_field1 (
    id integer NOT NULL,
    name character varying(256) NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_visit_field1 OWNER TO prod_kelava;

--
-- Name: m_field1_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_field1_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_field1_id_seq OWNER TO prod_kelava;

--
-- Name: m_field1_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_field1_id_seq OWNED BY public.m_visit_field1.id;


--
-- Name: m_hardware_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_hardware_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_hardware_id_seq OWNER TO prod_kelava;

--
-- Name: m_hardware; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_hardware (
    id integer DEFAULT nextval('public.m_hardware_id_seq'::regclass) NOT NULL,
    type character varying(256) NOT NULL,
    brand character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    status character varying(256) NOT NULL,
    remarks character varying(256),
    serial_number character varying(256) NOT NULL,
    photo character varying(256)
);


ALTER TABLE public.m_hardware OWNER TO prod_kelava;

--
-- Name: m_hour; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_hour (
    jam character(10) NOT NULL,
    sequence smallint NOT NULL
);


ALTER TABLE public.m_hour OWNER TO prod_kelava;

--
-- Name: m_knowledge; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_knowledge (
    id integer NOT NULL,
    title character varying(256) NOT NULL,
    description text,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT now(),
    id_client integer NOT NULL
);


ALTER TABLE public.m_knowledge OWNER TO prod_kelava;

--
-- Name: m_knowledge_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_knowledge_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_knowledge_id_seq OWNER TO prod_kelava;

--
-- Name: m_knowledge_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_knowledge_id_seq OWNED BY public.m_knowledge.id;


--
-- Name: m_membership_client; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_membership_client (
    id integer NOT NULL,
    id_membership_type integer NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_membership_client OWNER TO prod_kelava;

--
-- Name: m_membership_customer; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_membership_customer (
    id integer NOT NULL,
    id_membership integer NOT NULL,
    id_customer integer NOT NULL,
    start_date date NOT NULL,
    end_date date,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    created_date timestamp with time zone DEFAULT now() NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_membership_customer OWNER TO prod_kelava;

--
-- Name: m_membership_customer_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_membership_customer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_membership_customer_id_seq OWNER TO prod_kelava;

--
-- Name: m_membership_customer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_membership_customer_id_seq OWNED BY public.m_membership_customer.id;


--
-- Name: m_membership_level; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_membership_level (
    id integer NOT NULL,
    level character varying(256) NOT NULL,
    id_client integer NOT NULL,
    disc numeric DEFAULT '0'::numeric NOT NULL,
    scale_points integer DEFAULT 0 NOT NULL,
    birthday_points integer DEFAULT 0,
    period integer DEFAULT 12 NOT NULL,
    start_points integer DEFAULT 0,
    minimum_points integer DEFAULT 0,
    price numeric DEFAULT '0'::numeric,
    updated_by integer NOT NULL,
    updated_date timestamp with time zone DEFAULT now() NOT NULL,
    is_default smallint,
    add_to_nonmember smallint DEFAULT '0'::smallint
);


ALTER TABLE public.m_membership_level OWNER TO prod_kelava;

--
-- Name: COLUMN m_membership_level.period; Type: COMMENT; Schema: public; Owner: prod_kelava
--

COMMENT ON COLUMN public.m_membership_level.period IS 'months';


--
-- Name: m_membership_level_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_membership_level_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_membership_level_id_seq OWNER TO prod_kelava;

--
-- Name: m_membership_level_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_membership_level_id_seq OWNED BY public.m_membership_level.id;


--
-- Name: m_membership_type; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_membership_type (
    id integer NOT NULL,
    type character varying(256) NOT NULL
);


ALTER TABLE public.m_membership_type OWNER TO prod_kelava;

--
-- Name: m_membership_type_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_membership_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_membership_type_id_seq OWNER TO prod_kelava;

--
-- Name: m_membership_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_membership_type_id_seq OWNED BY public.m_membership_type.id;


--
-- Name: m_opportunity_stage; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_opportunity_stage (
    id integer NOT NULL,
    stage character varying(256) NOT NULL,
    sequence integer NOT NULL,
    id_client integer NOT NULL,
    is_final character varying(10) DEFAULT 'N'::character varying NOT NULL
);


ALTER TABLE public.m_opportunity_stage OWNER TO prod_kelava;

--
-- Name: m_opportunity_stage_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_opportunity_stage_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_opportunity_stage_id_seq OWNER TO prod_kelava;

--
-- Name: m_opportunity_stage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_opportunity_stage_id_seq OWNED BY public.m_opportunity_stage.id;


--
-- Name: m_outlet; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_outlet (
    id integer NOT NULL,
    nama character varying(256) NOT NULL,
    alamat text,
    telpon character varying(256),
    latitude character varying(256),
    longitude character varying(256),
    m_area integer NOT NULL,
    created_time timestamp without time zone NOT NULL,
    info text,
    kota character varying(256),
    provinsi character varying(256),
    negara character varying(256),
    code character varying(256),
    is_live integer DEFAULT 1 NOT NULL,
    mon_start time without time zone,
    mon_end time without time zone,
    tue_start time without time zone,
    tue_end time without time zone,
    wed_start time without time zone,
    wed_end time without time zone,
    thu_start time without time zone,
    thu_end time without time zone,
    fri_start time without time zone,
    fri_end time without time zone,
    sat_start time without time zone,
    sat_end time without time zone,
    sun_start time without time zone,
    sun_end time without time zone,
    id_client integer,
    img_url text
);


ALTER TABLE public.m_outlet OWNER TO prod_kelava;

--
-- Name: m_outlet_complement; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_outlet_complement (
    id integer NOT NULL,
    m_outlet integer NOT NULL,
    m_complement integer NOT NULL,
    created_date timestamp without time zone NOT NULL
);


ALTER TABLE public.m_outlet_complement OWNER TO prod_kelava;

--
-- Name: m_outlet_complement_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_outlet_complement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_complement_id_seq OWNER TO prod_kelava;

--
-- Name: m_outlet_complement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_outlet_complement_id_seq OWNED BY public.m_outlet_complement.id;


--
-- Name: m_outlet_complement_new; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_outlet_complement_new (
    created_date timestamp with time zone DEFAULT now() NOT NULL,
    id integer NOT NULL,
    id_outlet integer NOT NULL,
    id_product_complement integer NOT NULL
);


ALTER TABLE public.m_outlet_complement_new OWNER TO prod_kelava;

--
-- Name: m_outlet_complement_new_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_outlet_complement_new_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_complement_new_id_seq OWNER TO prod_kelava;

--
-- Name: m_outlet_complement_new_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_outlet_complement_new_id_seq OWNED BY public.m_outlet_complement_new.id;


--
-- Name: m_outlet_complement_price; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_outlet_complement_price (
    id integer NOT NULL,
    id_outlet_complement integer NOT NULL,
    price integer NOT NULL,
    start_date timestamp without time zone NOT NULL,
    created_date timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.m_outlet_complement_price OWNER TO prod_kelava;

--
-- Name: m_outlet_complement_price_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_outlet_complement_price_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_complement_price_id_seq OWNER TO prod_kelava;

--
-- Name: m_outlet_complement_price_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_outlet_complement_price_id_seq OWNED BY public.m_outlet_complement_price.id;


--
-- Name: m_outlet_complement_price_new; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.m_outlet_complement_price_new (
    created_date timestamp with time zone DEFAULT now(),
    id integer NOT NULL,
    id_outlet_complement integer NOT NULL,
    price numeric NOT NULL,
    start_date date NOT NULL
);


ALTER TABLE public.m_outlet_complement_price_new OWNER TO postgres;

--
-- Name: m_outlet_complement_price_new_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.m_outlet_complement_price_new_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_complement_price_new_id_seq OWNER TO postgres;

--
-- Name: m_outlet_complement_price_new_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.m_outlet_complement_price_new_id_seq OWNED BY public.m_outlet_complement_price_new.id;


--
-- Name: m_outlet_has_channel_pembayaran; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_outlet_has_channel_pembayaran (
    channel_pembayaran integer NOT NULL,
    id integer NOT NULL,
    m_outlet integer NOT NULL
);


ALTER TABLE public.m_outlet_has_channel_pembayaran OWNER TO prod_kelava;

--
-- Name: m_outlet_has_channel_pembayaran_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_outlet_has_channel_pembayaran_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_has_channel_pembayaran_id_seq OWNER TO prod_kelava;

--
-- Name: m_outlet_has_channel_pembayaran_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_outlet_has_channel_pembayaran_id_seq OWNED BY public.m_outlet_has_channel_pembayaran.id;


--
-- Name: m_outlet_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_outlet_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_id_seq OWNER TO prod_kelava;

--
-- Name: m_outlet_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_outlet_id_seq OWNED BY public.m_outlet.id;


--
-- Name: m_outlet_pic; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_outlet_pic (
    id integer NOT NULL,
    id_outlet integer NOT NULL,
    url text NOT NULL
);


ALTER TABLE public.m_outlet_pic OWNER TO prod_kelava;

--
-- Name: m_outlet_pic_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_outlet_pic_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_pic_id_seq OWNER TO prod_kelava;

--
-- Name: m_outlet_pic_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_outlet_pic_id_seq OWNED BY public.m_outlet_pic.id;


--
-- Name: m_outlet_queue_ads; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_outlet_queue_ads (
    created_time timestamp without time zone NOT NULL,
    file_url character varying(256) NOT NULL,
    id integer NOT NULL,
    id_client integer NOT NULL,
    id_outlet integer NOT NULL,
    type character varying(256) NOT NULL
);


ALTER TABLE public.m_outlet_queue_ads OWNER TO prod_kelava;

--
-- Name: m_outlet_queue_ads_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_outlet_queue_ads_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_queue_ads_id_seq OWNER TO prod_kelava;

--
-- Name: m_outlet_queue_ads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_outlet_queue_ads_id_seq OWNED BY public.m_outlet_queue_ads.id;


--
-- Name: m_outlet_setting; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.m_outlet_setting (
    id integer NOT NULL,
    id_client integer NOT NULL,
    item character varying(256) NOT NULL
);


ALTER TABLE public.m_outlet_setting OWNER TO postgres;

--
-- Name: m_outlet_setting_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.m_outlet_setting_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_setting_id_seq OWNER TO postgres;

--
-- Name: m_outlet_setting_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.m_outlet_setting_id_seq OWNED BY public.m_outlet_setting.id;


--
-- Name: m_outlet_setting_value; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.m_outlet_setting_value (
    id integer NOT NULL,
    id_outlet integer NOT NULL,
    id_outlet_setting integer NOT NULL,
    value text NOT NULL
);


ALTER TABLE public.m_outlet_setting_value OWNER TO postgres;

--
-- Name: m_outlet_setting_value_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.m_outlet_setting_value_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_outlet_setting_value_id_seq OWNER TO postgres;

--
-- Name: m_outlet_setting_value_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.m_outlet_setting_value_id_seq OWNED BY public.m_outlet_setting_value.id;


--
-- Name: m_package; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_package (
    id integer NOT NULL,
    package_name character varying(256) NOT NULL,
    fee numeric NOT NULL,
    menu_prefix character varying
);


ALTER TABLE public.m_package OWNER TO prod_kelava;

--
-- Name: m_package_conf; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_package_conf (
    id integer NOT NULL,
    m_package integer NOT NULL,
    model_class character varying(256) NOT NULL,
    max_value integer
);


ALTER TABLE public.m_package_conf OWNER TO prod_kelava;

--
-- Name: m_package_conf_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_package_conf_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_package_conf_id_seq OWNER TO prod_kelava;

--
-- Name: m_package_conf_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_package_conf_id_seq OWNED BY public.m_package_conf.id;


--
-- Name: m_package_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_package_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_package_id_seq OWNER TO prod_kelava;

--
-- Name: m_package_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_package_id_seq OWNED BY public.m_package.id;


--
-- Name: m_product_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_product_id_seq OWNER TO prod_kelava;

--
-- Name: m_product; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product (
    id integer DEFAULT nextval('public.m_product_id_seq'::regclass) NOT NULL,
    name character varying(256) NOT NULL,
    code character varying(256) NOT NULL,
    code_model character varying(256),
    unit character varying(256),
    code_group_mat character varying(256),
    id_brand integer,
    id_category integer,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    unit_1 character varying(256) NOT NULL,
    ratio_1 numeric DEFAULT '0'::numeric,
    unit_2 character varying(256),
    ratio_2 numeric DEFAULT '0'::numeric,
    unit_3 character varying(256),
    ratio_3 numeric DEFAULT '0'::numeric,
    unit_4 character varying(256),
    ratio_4 numeric DEFAULT '0'::numeric,
    id_client integer NOT NULL,
    featured_img character varying(256),
    url_pic text,
    description text,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    default_complementary integer DEFAULT 0 NOT NULL,
    id_product_type integer,
    is_stock smallint DEFAULT '0'::smallint NOT NULL,
    group_pelengkap character varying(256)
);


ALTER TABLE public.m_product OWNER TO prod_kelava;

--
-- Name: m_product_bom; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_bom (
    id integer NOT NULL,
    id_client integer NOT NULL,
    id_product integer NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    updated_by integer,
    updated_date timestamp with time zone
);


ALTER TABLE public.m_product_bom OWNER TO prod_kelava;

--
-- Name: m_product_bom_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_bom_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_bom_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_bom_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_product_bom_id_seq OWNED BY public.m_product_bom.id;


--
-- Name: m_product_bomdetail; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_bomdetail (
    id integer NOT NULL,
    id_product_bom integer NOT NULL,
    id_product_material integer NOT NULL,
    qty numeric NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    updated_by integer,
    updated_date timestamp with time zone
);


ALTER TABLE public.m_product_bomdetail OWNER TO prod_kelava;

--
-- Name: m_product_bomdetail_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_bomdetail_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_bomdetail_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_bomdetail_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_product_bomdetail_id_seq OWNED BY public.m_product_bomdetail.id;


--
-- Name: m_product_brand_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_brand_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_product_brand_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_brand; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_brand (
    id integer DEFAULT nextval('public.m_product_brand_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    id_client integer DEFAULT 1
);


ALTER TABLE public.m_product_brand OWNER TO prod_kelava;

--
-- Name: m_product_category_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_product_category_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_category; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_category (
    id integer DEFAULT nextval('public.m_product_category_id_seq'::regclass) NOT NULL,
    category character varying(256) NOT NULL,
    id_client integer NOT NULL,
    sequence smallint DEFAULT '1'::smallint NOT NULL
);


ALTER TABLE public.m_product_category OWNER TO prod_kelava;

--
-- Name: m_product_complement; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_complement (
    id integer NOT NULL,
    id_product integer NOT NULL,
    name character varying(256) NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    id_client integer NOT NULL,
    type character varying(256) NOT NULL,
    is_default smallint DEFAULT '0'::smallint NOT NULL
);


ALTER TABLE public.m_product_complement OWNER TO prod_kelava;

--
-- Name: m_product_complement_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_complement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_complement_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_complement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_product_complement_id_seq OWNED BY public.m_product_complement.id;


--
-- Name: m_product_complement_new; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.m_product_complement_new (
    id integer NOT NULL,
    id_client integer NOT NULL,
    id_product integer NOT NULL,
    id_product_complement integer NOT NULL
);


ALTER TABLE public.m_product_complement_new OWNER TO postgres;

--
-- Name: m_product_complement_id_seq1; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.m_product_complement_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_complement_id_seq1 OWNER TO postgres;

--
-- Name: m_product_complement_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.m_product_complement_id_seq1 OWNED BY public.m_product_complement_new.id;


--
-- Name: m_product_group_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_product_group_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_group; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_group (
    id integer DEFAULT nextval('public.m_product_group_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_product_group OWNER TO prod_kelava;

--
-- Name: m_product_material; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_material (
    id integer NOT NULL,
    id_client integer NOT NULL,
    product_material_name character varying(256) NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    updated_by integer,
    updated_date timestamp with time zone,
    uom character varying(156) NOT NULL
);


ALTER TABLE public.m_product_material OWNER TO prod_kelava;

--
-- Name: m_product_material_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_material_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_material_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_material_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_product_material_id_seq OWNED BY public.m_product_material.id;


--
-- Name: m_product_outlet; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_outlet (
    id integer NOT NULL,
    id_product integer NOT NULL,
    id_outlet integer NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_product_outlet OWNER TO prod_kelava;

--
-- Name: m_product_outlet_customer_group; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.m_product_outlet_customer_group (
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    id integer NOT NULL,
    id_client integer NOT NULL,
    id_customer_group integer NOT NULL,
    id_product_outlet integer NOT NULL,
    price numeric NOT NULL,
    start_date date NOT NULL
);


ALTER TABLE public.m_product_outlet_customer_group OWNER TO postgres;

--
-- Name: m_product_outlet_customer_group_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.m_product_outlet_customer_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_outlet_customer_group_id_seq OWNER TO postgres;

--
-- Name: m_product_outlet_customer_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.m_product_outlet_customer_group_id_seq OWNED BY public.m_product_outlet_customer_group.id;


--
-- Name: m_product_outlet_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_outlet_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_outlet_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_outlet_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_product_outlet_id_seq OWNED BY public.m_product_outlet.id;


--
-- Name: m_product_outlet_price; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_outlet_price (
    id integer NOT NULL,
    id_product_outlet integer NOT NULL,
    price numeric DEFAULT '0'::numeric NOT NULL,
    start_date date NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT now() NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_product_outlet_price OWNER TO prod_kelava;

--
-- Name: m_product_outlet_price_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_outlet_price_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_outlet_price_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_outlet_price_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_product_outlet_price_id_seq OWNED BY public.m_product_outlet_price.id;


--
-- Name: m_product_price_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_price_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_product_price_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_price; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_price (
    id integer DEFAULT nextval('public.m_product_price_id_seq'::regclass) NOT NULL,
    price numeric NOT NULL,
    valid_from date NOT NULL,
    valid_until date,
    status character varying(256),
    unit character varying(256),
    price_non_ppn numeric,
    id_product integer NOT NULL,
    id_contract integer,
    id_area integer,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_product_price OWNER TO prod_kelava;

--
-- Name: m_product_subcategory; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_subcategory (
    id integer NOT NULL,
    id_product_category integer NOT NULL,
    subcategory character varying(56) NOT NULL,
    status character varying(256) DEFAULT 'active'::character varying NOT NULL,
    sequence smallint DEFAULT '1'::smallint
);


ALTER TABLE public.m_product_subcategory OWNER TO prod_kelava;

--
-- Name: m_product_subcategory_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_subcategory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_subcategory_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_subcategory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_product_subcategory_id_seq OWNED BY public.m_product_subcategory.id;


--
-- Name: m_product_subgroup_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_subgroup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_product_subgroup_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_subgroup; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_subgroup (
    id integer DEFAULT nextval('public.m_product_subgroup_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    id_group integer NOT NULL
);


ALTER TABLE public.m_product_subgroup OWNER TO prod_kelava;

--
-- Name: m_product_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.m_product_type (
    id integer NOT NULL,
    type character varying(256) NOT NULL
);


ALTER TABLE public.m_product_type OWNER TO postgres;

--
-- Name: m_product_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.m_product_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_type_id_seq OWNER TO postgres;

--
-- Name: m_product_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.m_product_type_id_seq OWNED BY public.m_product_type.id;


--
-- Name: m_product_unit; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_product_unit (
    id integer NOT NULL,
    unit character varying(256) NOT NULL,
    ratio numeric NOT NULL
);


ALTER TABLE public.m_product_unit OWNER TO prod_kelava;

--
-- Name: m_product_unit_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_product_unit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_product_unit_id_seq OWNER TO prod_kelava;

--
-- Name: m_product_unit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_product_unit_id_seq OWNED BY public.m_product_unit.id;


--
-- Name: m_province_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_province_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_province_id_seq OWNER TO prod_kelava;

--
-- Name: m_province; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_province (
    id integer DEFAULT nextval('public.m_province_id_seq'::regclass) NOT NULL,
    name character varying(256) NOT NULL,
    code character varying(256) NOT NULL,
    id_country integer NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_province OWNER TO prod_kelava;

--
-- Name: m_region_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_region_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_region_id_seq OWNER TO prod_kelava;

--
-- Name: m_region; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_region (
    id integer DEFAULT nextval('public.m_region_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL
);


ALTER TABLE public.m_region OWNER TO prod_kelava;

--
-- Name: m_setting; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_setting (
    id integer NOT NULL,
    item character varying(256) NOT NULL
);


ALTER TABLE public.m_setting OWNER TO prod_kelava;

--
-- Name: m_setting_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_setting_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_setting_id_seq OWNER TO prod_kelava;

--
-- Name: m_setting_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_setting_id_seq OWNED BY public.m_setting.id;


--
-- Name: m_setting_value; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_setting_value (
    id integer NOT NULL,
    id_setting integer NOT NULL,
    value character varying(256) NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_setting_value OWNER TO prod_kelava;

--
-- Name: m_setting_value_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_setting_value_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_setting_value_id_seq OWNER TO prod_kelava;

--
-- Name: m_setting_value_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_setting_value_id_seq OWNED BY public.m_setting_value.id;


--
-- Name: m_sosmed; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_sosmed (
    id integer NOT NULL,
    id_client integer NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    sosmed character varying NOT NULL
);


ALTER TABLE public.m_sosmed OWNER TO prod_kelava;

--
-- Name: m_sosmed_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_sosmed_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_sosmed_id_seq OWNER TO prod_kelava;

--
-- Name: m_sosmed_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_sosmed_id_seq OWNED BY public.m_sosmed.id;


--
-- Name: m_subarea_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_subarea_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_subarea_id_seq OWNER TO prod_kelava;

--
-- Name: m_subarea; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_subarea (
    id integer DEFAULT nextval('public.m_subarea_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    id_area integer NOT NULL
);


ALTER TABLE public.m_subarea OWNER TO prod_kelava;

--
-- Name: m_subregion_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_subregion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.m_subregion_id_seq OWNER TO prod_kelava;

--
-- Name: m_subregion; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_subregion (
    id integer DEFAULT nextval('public.m_subregion_id_seq'::regclass) NOT NULL,
    code character varying(256) NOT NULL,
    name character varying(256) NOT NULL,
    id_region integer NOT NULL
);


ALTER TABLE public.m_subregion OWNER TO prod_kelava;

--
-- Name: m_totem; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_totem (
    created_date timestamp without time zone NOT NULL,
    deskripsi character varying(256) NOT NULL,
    id integer NOT NULL,
    id_client integer NOT NULL,
    id_outlet integer NOT NULL,
    id_user integer NOT NULL,
    is_active character varying(3) DEFAULT 'YES'::character varying NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    totem_code character varying(256) NOT NULL
);


ALTER TABLE public.m_totem OWNER TO prod_kelava;

--
-- Name: m_totem_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_totem_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_totem_id_seq OWNER TO prod_kelava;

--
-- Name: m_totem_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_totem_id_seq OWNED BY public.m_totem.id;


--
-- Name: m_visit_field2; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_visit_field2 (
    id integer NOT NULL,
    name character varying(256) NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_visit_field2 OWNER TO prod_kelava;

--
-- Name: m_visit_field2_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_visit_field2_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_visit_field2_id_seq OWNER TO prod_kelava;

--
-- Name: m_visit_field2_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_visit_field2_id_seq OWNED BY public.m_visit_field2.id;


--
-- Name: m_visit_field3; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.m_visit_field3 (
    id integer NOT NULL,
    name character varying(256) NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.m_visit_field3 OWNER TO prod_kelava;

--
-- Name: m_visit_field3_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.m_visit_field3_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.m_visit_field3_id_seq OWNER TO prod_kelava;

--
-- Name: m_visit_field3_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.m_visit_field3_id_seq OWNED BY public.m_visit_field3.id;


--
-- Name: p_migration; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.p_migration (
    version character varying(180) NOT NULL,
    apply_time integer
);


ALTER TABLE public.p_migration OWNER TO prod_kelava;

--
-- Name: p_project_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.p_project_id_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.p_project_id_seq OWNER TO prod_kelava;

--
-- Name: p_request_reset_password; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.p_request_reset_password (
    id integer NOT NULL,
    id_user integer NOT NULL,
    token character varying(256) NOT NULL,
    created_date timestamp with time zone DEFAULT now() NOT NULL,
    valid_to timestamp with time zone NOT NULL,
    is_used integer DEFAULT 0 NOT NULL,
    phone character varying(14)
);


ALTER TABLE public.p_request_reset_password OWNER TO prod_kelava;

--
-- Name: p_request_reset_password_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.p_request_reset_password_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.p_request_reset_password_id_seq OWNER TO prod_kelava;

--
-- Name: p_request_reset_password_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.p_request_reset_password_id_seq OWNED BY public.p_request_reset_password.id;


--
-- Name: p_role_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.p_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.p_role_id_seq OWNER TO prod_kelava;

--
-- Name: p_role; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.p_role (
    id integer DEFAULT nextval('public.p_role_id_seq'::regclass) NOT NULL,
    role_name character varying(256) NOT NULL,
    role_description character varying(256) NOT NULL,
    menu_path character varying(256),
    home_url character varying(256),
    repo_path character varying(256),
    is_web integer
);


ALTER TABLE public.p_role OWNER TO prod_kelava;

--
-- Name: p_user_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.p_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.p_user_id_seq OWNER TO prod_kelava;

--
-- Name: p_user; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.p_user (
    id integer DEFAULT nextval('public.p_user_id_seq'::regclass) NOT NULL,
    email character varying(256) NOT NULL,
    username character varying(256) NOT NULL,
    password character varying(256) NOT NULL,
    last_login timestamp without time zone,
    is_deleted boolean,
    fullname character varying(256),
    user_token character varying(256) NOT NULL,
    id_client integer,
    is_owner integer DEFAULT 0,
    is_verified character(1) DEFAULT 'N'::bpchar NOT NULL,
    token character varying(10),
    act_key character varying(256),
    reg_date timestamp without time zone,
    id_outlet integer,
    phone character varying(14)
);


ALTER TABLE public.p_user OWNER TO prod_kelava;

--
-- Name: p_user_role_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.p_user_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.p_user_role_id_seq OWNER TO prod_kelava;

--
-- Name: p_user_role; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.p_user_role (
    id integer DEFAULT nextval('public.p_user_role_id_seq'::regclass) NOT NULL,
    user_id integer NOT NULL,
    role_id integer NOT NULL,
    is_default_role character varying(256) DEFAULT 'No'::character varying
);


ALTER TABLE public.p_user_role OWNER TO prod_kelava;

--
-- Name: temp_employee_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.temp_employee_id_seq
    START WITH 3
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.temp_employee_id_seq OWNER TO prod_kelava;

--
-- Name: pr_employee; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.pr_employee (
    id integer DEFAULT nextval('public.temp_employee_id_seq'::regclass) NOT NULL,
    name character varying(256) NOT NULL
);


ALTER TABLE public.pr_employee OWNER TO prod_kelava;

--
-- Name: pr_project; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.pr_project (
    id integer DEFAULT nextval('public.p_project_id_seq'::regclass) NOT NULL,
    name character varying(256) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    contract_no character varying(256) NOT NULL,
    price numeric DEFAULT '0'::numeric NOT NULL,
    description text,
    pic integer NOT NULL
);


ALTER TABLE public.pr_project OWNER TO prod_kelava;

--
-- Name: pr_target_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.pr_target_id_seq
    START WITH 9
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.pr_target_id_seq OWNER TO prod_kelava;

--
-- Name: pr_target; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.pr_target (
    id integer DEFAULT nextval('public.pr_target_id_seq'::regclass) NOT NULL,
    tgl date NOT NULL,
    target numeric NOT NULL,
    aktual numeric
);


ALTER TABLE public.pr_target OWNER TO prod_kelava;

--
-- Name: temp_task_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.temp_task_id_seq
    START WITH 5
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.temp_task_id_seq OWNER TO prod_kelava;

--
-- Name: pr_task; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.pr_task (
    id integer DEFAULT nextval('public.temp_task_id_seq'::regclass) NOT NULL,
    name character varying(256) NOT NULL,
    start_date date,
    end_date date,
    progress numeric NOT NULL,
    bobot numeric DEFAULT '0'::numeric NOT NULL,
    id_project integer NOT NULL,
    id_task_parent integer,
    id_employee integer
);


ALTER TABLE public.pr_task OWNER TO prod_kelava;

--
-- Name: temp_task_emp_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.temp_task_emp_id_seq
    START WITH 6
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.temp_task_emp_id_seq OWNER TO prod_kelava;

--
-- Name: pr_task_emp; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.pr_task_emp (
    id integer DEFAULT nextval('public.temp_task_emp_id_seq'::regclass) NOT NULL,
    id_task integer NOT NULL,
    id_employee integer NOT NULL
);


ALTER TABLE public.pr_task_emp OWNER TO prod_kelava;

--
-- Name: pr_task_product_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.pr_task_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.pr_task_product_id_seq OWNER TO prod_kelava;

--
-- Name: pr_task_realization_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.pr_task_realization_id_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.pr_task_realization_id_seq OWNER TO prod_kelava;

--
-- Name: pr_task_realization; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.pr_task_realization (
    id integer DEFAULT nextval('public.pr_task_realization_id_seq'::regclass) NOT NULL,
    date_relization date NOT NULL,
    remarks text NOT NULL,
    id_task integer NOT NULL,
    progress numeric NOT NULL
);


ALTER TABLE public.pr_task_realization OWNER TO prod_kelava;

--
-- Name: s_pos; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.s_pos (
    user_id integer NOT NULL,
    id_client integer NOT NULL,
    app_token character varying(256) NOT NULL,
    user_token character varying(256) NOT NULL,
    sess_id character varying(256) NOT NULL,
    created_time timestamp without time zone NOT NULL,
    app_name character varying(256) NOT NULL,
    server_url character varying(256) NOT NULL,
    id integer NOT NULL,
    id_outlet integer
);


ALTER TABLE public.s_pos OWNER TO prod_kelava;

--
-- Name: s_pos_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.s_pos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.s_pos_id_seq OWNER TO prod_kelava;

--
-- Name: s_pos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.s_pos_id_seq OWNED BY public.s_pos.id;


--
-- Name: t_customer_group_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.t_customer_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_customer_group_id_seq OWNER TO postgres;

--
-- Name: t_customer_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.t_customer_group_id_seq OWNED BY public.m_customer_group.id;


--
-- Name: t_customer_poin; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_customer_poin (
    id integer NOT NULL,
    id_customer integer NOT NULL,
    id_membership_level integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    poin integer DEFAULT 0 NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    transaction_amount numeric DEFAULT '0'::numeric NOT NULL,
    expired_date date,
    id_sales_order integer,
    remarks character varying(256)
);


ALTER TABLE public.t_customer_poin OWNER TO prod_kelava;

--
-- Name: t_customer_poin_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_customer_poin_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_customer_poin_id_seq OWNER TO prod_kelava;

--
-- Name: t_customer_poin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_customer_poin_id_seq OWNED BY public.t_customer_poin.id;


--
-- Name: t_event; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_event (
    id integer DEFAULT nextval('public.event_id_seq'::regclass) NOT NULL,
    location character varying(256) NOT NULL,
    start_date date NOT NULL,
    remarks character varying(256),
    target character varying(256) NOT NULL,
    contact_person_name character varying(256) NOT NULL,
    contact_person_phone character varying(256) NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT (CURRENT_TIMESTAMP + '00:00:00'::interval) NOT NULL,
    end_date date NOT NULL,
    title character varying(256) NOT NULL
);


ALTER TABLE public.t_event OWNER TO prod_kelava;

--
-- Name: t_event_pic; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_event_pic (
    id integer NOT NULL,
    id_event integer NOT NULL,
    id_user integer NOT NULL
);


ALTER TABLE public.t_event_pic OWNER TO prod_kelava;

--
-- Name: t_event_pic_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_event_pic_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_event_pic_id_seq OWNER TO prod_kelava;

--
-- Name: t_event_pic_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_event_pic_id_seq OWNED BY public.t_event_pic.id;


--
-- Name: t_event_assign; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_event_assign (
    id integer DEFAULT nextval('public.t_event_pic_id_seq'::regclass) NOT NULL,
    id_event integer NOT NULL,
    id_user integer NOT NULL
);


ALTER TABLE public.t_event_assign OWNER TO prod_kelava;

--
-- Name: t_event_assign_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_event_assign_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_event_assign_id_seq OWNER TO prod_kelava;

--
-- Name: t_event_result_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_event_result_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_event_result_id_seq OWNER TO prod_kelava;

--
-- Name: t_event_result; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_event_result (
    id integer DEFAULT nextval('public.t_event_result_id_seq'::regclass) NOT NULL,
    id_product integer NOT NULL,
    qty numeric NOT NULL,
    remarks character varying(256),
    id_event integer NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT (now() + '00:00:00'::interval) NOT NULL,
    photo character varying
);


ALTER TABLE public.t_event_result OWNER TO prod_kelava;

--
-- Name: t_hardware_usage_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_hardware_usage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_hardware_usage_id_seq OWNER TO prod_kelava;

--
-- Name: t_hardware_usage; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_hardware_usage (
    id integer DEFAULT nextval('public.t_hardware_usage_id_seq'::regclass) NOT NULL,
    status character varying(256) NOT NULL,
    id_hardware integer NOT NULL,
    id_event integer,
    id_contract integer,
    start_date date NOT NULL,
    end_date date NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL
);


ALTER TABLE public.t_hardware_usage OWNER TO prod_kelava;

--
-- Name: COLUMN t_hardware_usage.status; Type: COMMENT; Schema: public; Owner: prod_kelava
--

COMMENT ON COLUMN public.t_hardware_usage.status IS '[Terkirim/Belum Terkirim/Sudah Kembali]';


--
-- Name: t_hit; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_hit (
    id integer NOT NULL,
    title character varying(256) NOT NULL,
    id_customer integer,
    id_cilent integer NOT NULL,
    created_date timestamp with time zone DEFAULT now() NOT NULL,
    id_user integer
);


ALTER TABLE public.t_hit OWNER TO prod_kelava;

--
-- Name: t_hit_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_hit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_hit_id_seq OWNER TO prod_kelava;

--
-- Name: t_hit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_hit_id_seq OWNED BY public.t_hit.id;


--
-- Name: t_invoice; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_invoice (
    id integer NOT NULL,
    inv_no character varying(256) NOT NULL,
    inv_date timestamp with time zone NOT NULL,
    meta_data json NOT NULL,
    status character varying(256) NOT NULL,
    created_date timestamp with time zone NOT NULL,
    created_by integer NOT NULL,
    updated_date timestamp with time zone,
    updated_by integer,
    id_delivery integer NOT NULL,
    meta_data_response integer NOT NULL,
    type character varying(256)
);


ALTER TABLE public.t_invoice OWNER TO prod_kelava;

--
-- Name: t_invoice_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_invoice_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_invoice_id_seq OWNER TO prod_kelava;

--
-- Name: t_invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_invoice_id_seq OWNED BY public.t_invoice.id;


--
-- Name: t_log_payment_gateway; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_log_payment_gateway (
    id integer NOT NULL,
    invoice_no character varying(256) NOT NULL,
    merchant character varying(256) NOT NULL,
    method character varying(256) NOT NULL,
    data jsonb NOT NULL,
    response jsonb NOT NULL,
    result jsonb,
    id_client integer NOT NULL,
    id_outlet integer,
    created_date timestamp with time zone DEFAULT now(),
    status character varying(256),
    amount numeric
);


ALTER TABLE public.t_log_payment_gateway OWNER TO prod_kelava;

--
-- Name: t_log_payment_gateway_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_log_payment_gateway_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_log_payment_gateway_id_seq OWNER TO prod_kelava;

--
-- Name: t_log_payment_gateway_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_log_payment_gateway_id_seq OWNED BY public.t_log_payment_gateway.id;


--
-- Name: t_membership_client_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_membership_client_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_membership_client_id_seq OWNER TO prod_kelava;

--
-- Name: t_membership_client_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_membership_client_id_seq OWNED BY public.m_membership_client.id;


--
-- Name: t_news; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_news (
    id integer NOT NULL,
    title character varying(256) NOT NULL,
    description text NOT NULL,
    img_url text NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    link_url text,
    send_notification character(1) DEFAULT 'N'::bpchar NOT NULL,
    id_client integer NOT NULL,
    created_by integer DEFAULT 1 NOT NULL,
    created_date timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.t_news OWNER TO prod_kelava;

--
-- Name: t_news_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_news_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_news_id_seq OWNER TO prod_kelava;

--
-- Name: t_news_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_news_id_seq OWNED BY public.t_news.id;


--
-- Name: t_opportunity; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_opportunity (
    id integer NOT NULL,
    name character varying(256) NOT NULL,
    id_customer integer NOT NULL,
    id_stage integer NOT NULL,
    closed_date timestamp without time zone,
    amount numeric(15,2) DEFAULT '0'::numeric,
    created_by integer NOT NULL,
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    id_client integer NOT NULL,
    description text,
    remarks text,
    margin numeric(15,2) DEFAULT '0'::numeric,
    estimate_deal timestamp without time zone,
    id_outlet integer
);


ALTER TABLE public.t_opportunity OWNER TO prod_kelava;

--
-- Name: t_opportunity_file; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_opportunity_file (
    id integer NOT NULL,
    filename text NOT NULL,
    created_date timestamp without time zone DEFAULT now(),
    id_opportunity integer NOT NULL
);


ALTER TABLE public.t_opportunity_file OWNER TO prod_kelava;

--
-- Name: t_opportunity_file_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_opportunity_file_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_opportunity_file_id_seq OWNER TO prod_kelava;

--
-- Name: t_opportunity_file_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_opportunity_file_id_seq OWNED BY public.t_opportunity_file.id;


--
-- Name: t_opportunity_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_opportunity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_opportunity_id_seq OWNER TO prod_kelava;

--
-- Name: t_opportunity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_opportunity_id_seq OWNED BY public.t_opportunity.id;


--
-- Name: t_opportunity_timeline; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_opportunity_timeline (
    id integer NOT NULL,
    id_opportunity integer NOT NULL,
    id_stage integer NOT NULL,
    amount numeric(15,2) DEFAULT '0'::numeric,
    description text,
    remarks text,
    margin numeric(15,2) DEFAULT '0'::numeric,
    updated_by integer NOT NULL,
    updated_date timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.t_opportunity_timeline OWNER TO prod_kelava;

--
-- Name: t_opportunity_timeline_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_opportunity_timeline_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_opportunity_timeline_id_seq OWNER TO prod_kelava;

--
-- Name: t_opportunity_timeline_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_opportunity_timeline_id_seq OWNED BY public.t_opportunity_timeline.id;


--
-- Name: t_otp_log; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_otp_log (
    created_time timestamp without time zone NOT NULL,
    id integer NOT NULL,
    id_client integer NOT NULL,
    msg character varying(256),
    target_number character varying(256) NOT NULL
);


ALTER TABLE public.t_otp_log OWNER TO prod_kelava;

--
-- Name: t_otp_log_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_otp_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_otp_log_id_seq OWNER TO prod_kelava;

--
-- Name: t_otp_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_otp_log_id_seq OWNED BY public.t_otp_log.id;


--
-- Name: t_outlet_charges; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.t_outlet_charges (
    id integer NOT NULL,
    id_charges integer NOT NULL,
    id_outlet integer NOT NULL,
    label character varying(256),
    sequence integer DEFAULT 1 NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL
);


ALTER TABLE public.t_outlet_charges OWNER TO postgres;

--
-- Name: t_outlet_charges_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.t_outlet_charges_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_outlet_charges_id_seq OWNER TO postgres;

--
-- Name: t_outlet_charges_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.t_outlet_charges_id_seq OWNED BY public.t_outlet_charges.id;


--
-- Name: t_outlet_charges_value; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.t_outlet_charges_value (
    id integer NOT NULL,
    id_outlet_charges integer NOT NULL,
    updated_by integer,
    updated_date timestamp with time zone DEFAULT now(),
    valid_from date NOT NULL,
    value numeric DEFAULT '0'::numeric
);


ALTER TABLE public.t_outlet_charges_value OWNER TO postgres;

--
-- Name: t_outlet_charges_value_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.t_outlet_charges_value_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_outlet_charges_value_id_seq OWNER TO postgres;

--
-- Name: t_outlet_charges_value_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.t_outlet_charges_value_id_seq OWNED BY public.t_outlet_charges_value.id;


--
-- Name: t_outlet_promo; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_outlet_promo (
    id integer NOT NULL,
    id_product_outlet integer NOT NULL,
    price numeric DEFAULT '0'::numeric NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL
);


ALTER TABLE public.t_outlet_promo OWNER TO prod_kelava;

--
-- Name: t_outlet_promo_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_outlet_promo_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_outlet_promo_id_seq OWNER TO prod_kelava;

--
-- Name: t_outlet_promo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_outlet_promo_id_seq OWNED BY public.t_outlet_promo.id;


--
-- Name: t_outlet_queue_date_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_outlet_queue_date_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_outlet_queue_date_id_seq OWNER TO prod_kelava;

--
-- Name: t_outlet_queue_date; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_outlet_queue_date (
    id integer DEFAULT nextval('public.t_outlet_queue_date_id_seq'::regclass) NOT NULL,
    id_client integer NOT NULL,
    id_outlet integer NOT NULL,
    queue_date date NOT NULL
);


ALTER TABLE public.t_outlet_queue_date OWNER TO prod_kelava;

--
-- Name: t_outlet_queue_date_number; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_outlet_queue_date_number (
    id integer NOT NULL,
    id_outlet_queue_date integer NOT NULL,
    id_sales_order integer NOT NULL,
    queue integer NOT NULL,
    status integer
);


ALTER TABLE public.t_outlet_queue_date_number OWNER TO prod_kelava;

--
-- Name: t_outlet_queue_date_number_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_outlet_queue_date_number_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_outlet_queue_date_number_id_seq OWNER TO prod_kelava;

--
-- Name: t_outlet_queue_date_number_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_outlet_queue_date_number_id_seq OWNED BY public.t_outlet_queue_date_number.id;


--
-- Name: t_payment; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_payment (
    id integer NOT NULL,
    id_delivery integer NOT NULL,
    total_payment numeric NOT NULL,
    payment_method character varying(10) DEFAULT 'cash, tranfer, others'::character varying NOT NULL,
    notes text,
    attachment_url character varying(255),
    created_by integer NOT NULL,
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    id_client integer NOT NULL,
    cash numeric,
    change numeric
);


ALTER TABLE public.t_payment OWNER TO prod_kelava;

--
-- Name: t_payment_callback_response; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_payment_callback_response (
    id integer NOT NULL,
    id_payment_log integer NOT NULL,
    response json NOT NULL,
    created_date timestamp with time zone NOT NULL,
    status character varying(256) NOT NULL
);


ALTER TABLE public.t_payment_callback_response OWNER TO prod_kelava;

--
-- Name: t_payment_callback_response_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_payment_callback_response_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_payment_callback_response_id_seq OWNER TO prod_kelava;

--
-- Name: t_payment_callback_response_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_payment_callback_response_id_seq OWNED BY public.t_payment_callback_response.id;


--
-- Name: t_payment_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_payment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_payment_id_seq OWNER TO prod_kelava;

--
-- Name: t_payment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_payment_id_seq OWNED BY public.t_payment.id;


--
-- Name: t_product_outlet_movement; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_product_outlet_movement (
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    id integer NOT NULL,
    id_client integer NOT NULL,
    id_outlet integer NOT NULL,
    id_product integer NOT NULL,
    id_sales_order integer,
    qty double precision NOT NULL,
    status character varying(256) DEFAULT 'Posted'::character varying NOT NULL,
    type character varying(256) NOT NULL,
    updated_by integer,
    updated_date timestamp with time zone
);


ALTER TABLE public.t_product_outlet_movement OWNER TO prod_kelava;

--
-- Name: t_product_materialoutlet_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_product_materialoutlet_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_product_materialoutlet_id_seq OWNER TO prod_kelava;

--
-- Name: t_product_materialoutlet_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_product_materialoutlet_id_seq OWNED BY public.t_product_outlet_movement.id;


--
-- Name: t_product_outlet_stock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.t_product_outlet_stock (
    id integer NOT NULL,
    id_client integer NOT NULL,
    id_outlet integer NOT NULL,
    id_product integer NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    stock numeric NOT NULL
);


ALTER TABLE public.t_product_outlet_stock OWNER TO postgres;

--
-- Name: t_product_outlet_stock_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.t_product_outlet_stock_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_product_outlet_stock_id_seq OWNER TO postgres;

--
-- Name: t_product_outlet_stock_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.t_product_outlet_stock_id_seq OWNED BY public.t_product_outlet_stock.id;


--
-- Name: t_promo; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_promo (
    id integer NOT NULL,
    title text NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    description text NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL,
    status character varying(256) DEFAULT 'Active'::character varying NOT NULL,
    img_url text NOT NULL,
    is_national character varying(256) DEFAULT 'yes'::character varying NOT NULL,
    disc_amount numeric DEFAULT '0'::numeric NOT NULL,
    send_notification character(2) DEFAULT 'N'::bpchar NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.t_promo OWNER TO prod_kelava;

--
-- Name: t_promo_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_promo_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_promo_id_seq OWNER TO prod_kelava;

--
-- Name: t_promo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_promo_id_seq OWNED BY public.t_promo.id;


--
-- Name: t_purchase_order; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_purchase_order (
    id integer NOT NULL,
    po_date timestamp with time zone DEFAULT now() NOT NULL,
    id_vendor integer NOT NULL,
    invoice_no character varying(256),
    description character varying(256),
    status character varying(256) DEFAULT 'Open'::character varying NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT now() NOT NULL,
    sub_total double precision DEFAULT '0'::double precision NOT NULL,
    grand_total double precision DEFAULT '0'::double precision NOT NULL,
    id_client integer NOT NULL
);


ALTER TABLE public.t_purchase_order OWNER TO prod_kelava;

--
-- Name: t_purchase_order_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_purchase_order_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_purchase_order_id_seq OWNER TO prod_kelava;

--
-- Name: t_purchase_order_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_purchase_order_id_seq OWNED BY public.t_purchase_order.id;


--
-- Name: t_registration; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.t_registration (
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    id integer NOT NULL,
    id_client integer NOT NULL,
    phone character varying(256) NOT NULL,
    token character varying(256) NOT NULL
);


ALTER TABLE public.t_registration OWNER TO postgres;

--
-- Name: t_registration_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.t_registration_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_registration_id_seq OWNER TO postgres;

--
-- Name: t_registration_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.t_registration_id_seq OWNED BY public.t_registration.id;


--
-- Name: t_road_plan_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_road_plan_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_road_plan_id_seq OWNER TO prod_kelava;

--
-- Name: t_road_plan; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_road_plan (
    id integer DEFAULT nextval('public.t_road_plan_id_seq'::regclass) NOT NULL,
    visit_date timestamp with time zone NOT NULL,
    status character varying(256) NOT NULL,
    remarks text,
    id_user integer NOT NULL,
    id_approval integer,
    id_customer_outlet integer,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT (now() + '00:00:00'::interval) NOT NULL,
    type character varying(256) DEFAULT 'visit'::character varying NOT NULL,
    id_customer integer NOT NULL,
    id_client integer NOT NULL,
    title character varying(256),
    id_outlet integer
);


ALTER TABLE public.t_road_plan OWNER TO prod_kelava;

--
-- Name: COLUMN t_road_plan.status; Type: COMMENT; Schema: public; Owner: prod_kelava
--

COMMENT ON COLUMN public.t_road_plan.status IS 'Pending,Done,Progress';


--
-- Name: COLUMN t_road_plan.type; Type: COMMENT; Schema: public; Owner: prod_kelava
--

COMMENT ON COLUMN public.t_road_plan.type IS '[visit/meeting]';


--
-- Name: t_road_plan_approval_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_road_plan_approval_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_road_plan_approval_id_seq OWNER TO prod_kelava;

--
-- Name: t_road_plan_approval; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_road_plan_approval (
    id integer DEFAULT nextval('public.t_road_plan_approval_id_seq'::regclass) NOT NULL,
    id_approver integer NOT NULL,
    approval_date timestamp with time zone NOT NULL,
    status character varying(256) NOT NULL,
    remarks character varying(256),
    instruksi character varying(256)
);


ALTER TABLE public.t_road_plan_approval OWNER TO prod_kelava;

--
-- Name: COLUMN t_road_plan_approval.status; Type: COMMENT; Schema: public; Owner: prod_kelava
--

COMMENT ON COLUMN public.t_road_plan_approval.status IS 'Approved,Rejected';


--
-- Name: t_road_plan_sales_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_road_plan_sales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_road_plan_sales_id_seq OWNER TO prod_kelava;

--
-- Name: t_road_plan_sales; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_road_plan_sales (
    id integer DEFAULT nextval('public.t_road_plan_sales_id_seq'::regclass) NOT NULL,
    with_name character varying(256),
    with_company character varying(256),
    type character varying(256) NOT NULL,
    status character varying(256) NOT NULL,
    agenda character varying(256) NOT NULL,
    followup json NOT NULL,
    meta_data json DEFAULT json_build_object() NOT NULL,
    remarks character varying(256),
    id_road_plan integer NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT (now() + '00:00:00'::interval) NOT NULL
);


ALTER TABLE public.t_road_plan_sales OWNER TO prod_kelava;

--
-- Name: COLUMN t_road_plan_sales.status; Type: COMMENT; Schema: public; Owner: prod_kelava
--

COMMENT ON COLUMN public.t_road_plan_sales.status IS 'Follow-Up,Done';


--
-- Name: t_sales_order_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_order_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_sales_order_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_order; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_order (
    id integer DEFAULT nextval('public.t_sales_order_id_seq'::regclass) NOT NULL,
    sales_order_number character varying(256),
    purchase_order_number character varying(256),
    ppn double precision NOT NULL,
    no_faktur_pajak character varying(256),
    sales_order_date date NOT NULL,
    est_delivery timestamp with time zone,
    status character varying(256),
    posted_kiss character varying(256),
    created_by integer NOT NULL,
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    id_customer integer NOT NULL,
    id_customer_outlet integer,
    sub_total double precision DEFAULT '0'::numeric NOT NULL,
    grand_total double precision DEFAULT '0'::numeric NOT NULL,
    total_kg integer,
    amount_discount double precision,
    amount_ppn double precision,
    discount character varying,
    purchase_order_image character varying,
    id_client integer,
    id_outlet integer,
    meta_data json,
    customer_name character varying(256),
    qr_code text,
    src character varying(256),
    notes character varying(256)
);


ALTER TABLE public.t_sales_order OWNER TO prod_kelava;

--
-- Name: t_sales_order_delivery; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_order_delivery (
    id integer NOT NULL,
    id_sales_order integer NOT NULL,
    invoice_code character varying(50) NOT NULL,
    deliver_date timestamp without time zone NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp without time zone NOT NULL,
    sub_total numeric NOT NULL,
    grand_total numeric NOT NULL,
    amount_discount numeric DEFAULT '0'::numeric NOT NULL,
    amount_ppn numeric DEFAULT '0'::numeric NOT NULL,
    status character varying(256) DEFAULT 'Complete'::character varying,
    updated_by integer,
    updated_date timestamp with time zone
);


ALTER TABLE public.t_sales_order_delivery OWNER TO prod_kelava;

--
-- Name: t_sales_order_delivery_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_order_delivery_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_order_delivery_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_order_delivery_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_order_delivery_id_seq OWNED BY public.t_sales_order_delivery.id;


--
-- Name: t_sales_order_delivery_item; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_order_delivery_item (
    id integer NOT NULL,
    id_delivery integer NOT NULL,
    id_product integer NOT NULL,
    qty integer NOT NULL,
    id_delivery_item_status integer,
    updated_by integer,
    updated_date timestamp with time zone DEFAULT now(),
    id_sales_order_line integer
);


ALTER TABLE public.t_sales_order_delivery_item OWNER TO prod_kelava;

--
-- Name: t_sales_order_delivery_item_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_order_delivery_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_order_delivery_item_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_order_delivery_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_order_delivery_item_id_seq OWNED BY public.t_sales_order_delivery_item.id;


--
-- Name: t_sales_order_delivery_item_status; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_order_delivery_item_status (
    id integer NOT NULL,
    id_client integer NOT NULL,
    status character varying(256) NOT NULL,
    is_default smallint DEFAULT '0'::smallint,
    sequence smallint
);


ALTER TABLE public.t_sales_order_delivery_item_status OWNER TO prod_kelava;

--
-- Name: t_sales_order_delivery_item_status_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_order_delivery_item_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_order_delivery_item_status_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_order_delivery_item_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_order_delivery_item_status_id_seq OWNED BY public.t_sales_order_delivery_item_status.id;


--
-- Name: t_sales_order_line_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_order_line_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_sales_order_line_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_order_line; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_order_line (
    id integer DEFAULT nextval('public.t_sales_order_line_id_seq'::regclass) NOT NULL,
    id_sales_order integer NOT NULL,
    id_product integer NOT NULL,
    qty numeric DEFAULT '0'::numeric NOT NULL,
    unit character varying(256) NOT NULL,
    price double precision DEFAULT '0'::numeric NOT NULL,
    created_by integer,
    created_date timestamp with time zone DEFAULT (now() + '07:00:00'::interval) NOT NULL,
    total double precision DEFAULT '0'::numeric,
    qty_kg integer,
    subtotal double precision,
    amount_discount double precision,
    discount character varying,
    ratio numeric,
    meta_data json,
    product_price numeric DEFAULT '0'::numeric,
    status character varying(256) DEFAULT 'Active'::character varying,
    product_name character varying(256)
);


ALTER TABLE public.t_sales_order_line OWNER TO prod_kelava;

--
-- Name: t_sales_order_status_history; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_order_status_history (
    id integer NOT NULL,
    created_time timestamp without time zone NOT NULL,
    sales_order integer NOT NULL,
    status character varying(256) NOT NULL,
    info text,
    id_client integer NOT NULL
);


ALTER TABLE public.t_sales_order_status_history OWNER TO prod_kelava;

--
-- Name: t_sales_order_status_history_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_order_status_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_order_status_history_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_order_status_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_order_status_history_id_seq OWNED BY public.t_sales_order_status_history.id;


--
-- Name: t_sales_outlet_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_outlet_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_sales_outlet_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_outlet; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_outlet (
    id integer DEFAULT nextval('public.t_sales_outlet_id_seq'::regclass) NOT NULL,
    id_user integer NOT NULL,
    id_outlet integer NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone NOT NULL
);


ALTER TABLE public.t_sales_outlet OWNER TO prod_kelava;

--
-- Name: t_sales_target_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_target_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_sales_target_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_target; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_target (
    id integer DEFAULT nextval('public.t_sales_target_id_seq'::regclass) NOT NULL,
    month integer,
    year integer NOT NULL,
    level character varying(256) NOT NULL,
    amount numeric NOT NULL,
    percent numeric NOT NULL,
    id_by_level integer,
    id_area integer,
    id_customer_segment integer,
    id_user integer,
    id_product integer,
    id_customer_outlet integer,
    created_by integer NOT NULL,
    created_date timestamp without time zone NOT NULL,
    deviasi_percent numeric,
    id_subarea integer,
    remarks character varying(256),
    deviasi_amount numeric,
    id_target_company integer DEFAULT 1 NOT NULL
);


ALTER TABLE public.t_sales_target OWNER TO prod_kelava;

--
-- Name: t_sales_target_area; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_target_area (
    id integer NOT NULL,
    id_target_month integer NOT NULL,
    pct_target numeric NOT NULL,
    value_target numeric NOT NULL,
    id_area integer NOT NULL
);


ALTER TABLE public.t_sales_target_area OWNER TO prod_kelava;

--
-- Name: t_sales_target_area_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_target_area_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_target_area_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_target_area_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_target_area_id_seq OWNED BY public.t_sales_target_area.id;


--
-- Name: t_sales_target_company_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_target_company_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_sales_target_company_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_target_company; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_target_company (
    id integer DEFAULT nextval('public.t_sales_target_company_id_seq'::regclass) NOT NULL,
    year integer NOT NULL,
    target numeric NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp without time zone NOT NULL,
    id_client integer
);


ALTER TABLE public.t_sales_target_company OWNER TO prod_kelava;

--
-- Name: t_sales_target_month; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_target_month (
    id integer NOT NULL,
    id_target_company integer NOT NULL,
    pct_target numeric NOT NULL,
    value_target numeric NOT NULL,
    month character varying(256) NOT NULL,
    id_client integer
);


ALTER TABLE public.t_sales_target_month OWNER TO prod_kelava;

--
-- Name: t_sales_target_month_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_target_month_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_target_month_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_target_month_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_target_month_id_seq OWNED BY public.t_sales_target_month.id;


--
-- Name: t_sales_target_product; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_target_product (
    id integer NOT NULL,
    id_target_month integer NOT NULL,
    id_product_group integer NOT NULL,
    id_product integer NOT NULL,
    pct_target numeric NOT NULL,
    value_target numeric NOT NULL,
    id_user integer NOT NULL,
    qty_target numeric NOT NULL,
    deviasi_target numeric NOT NULL,
    qty_deviasi numeric NOT NULL,
    price numeric NOT NULL,
    id_client integer
);


ALTER TABLE public.t_sales_target_product OWNER TO prod_kelava;

--
-- Name: t_sales_target_product_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_target_product_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_target_product_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_target_product_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_target_product_id_seq OWNED BY public.t_sales_target_product.id;


--
-- Name: t_sales_target_salesman; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_target_salesman (
    id integer NOT NULL,
    id_target_segment integer NOT NULL,
    pct_target numeric NOT NULL,
    value_target numeric NOT NULL,
    remarks character varying(256),
    pct_deviasi numeric NOT NULL,
    deviasi_target numeric NOT NULL,
    id_user integer NOT NULL,
    id_client integer
);


ALTER TABLE public.t_sales_target_salesman OWNER TO prod_kelava;

--
-- Name: t_sales_target_salesman_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_target_salesman_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_target_salesman_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_target_salesman_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_target_salesman_id_seq OWNED BY public.t_sales_target_salesman.id;


--
-- Name: t_sales_target_segment; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_target_segment (
    id integer NOT NULL,
    id_target_subarea integer NOT NULL,
    pct_target numeric NOT NULL,
    value_target numeric NOT NULL,
    id_customer_segment integer NOT NULL,
    deviasi numeric NOT NULL,
    id_client integer
);


ALTER TABLE public.t_sales_target_segment OWNER TO prod_kelava;

--
-- Name: t_sales_target_segment_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_target_segment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_target_segment_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_target_segment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_target_segment_id_seq OWNED BY public.t_sales_target_segment.id;


--
-- Name: t_sales_target_store; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_target_store (
    id integer NOT NULL,
    id_target_month integer NOT NULL,
    id_outlet integer NOT NULL,
    pct_target numeric NOT NULL,
    value_target numeric NOT NULL,
    id_user integer NOT NULL,
    deviasi_target numeric NOT NULL,
    id_segment integer NOT NULL
);


ALTER TABLE public.t_sales_target_store OWNER TO prod_kelava;

--
-- Name: t_sales_target_store_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_target_store_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_target_store_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_target_store_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_target_store_id_seq OWNED BY public.t_sales_target_store.id;


--
-- Name: t_sales_target_subarea; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_sales_target_subarea (
    id integer NOT NULL,
    id_target_area integer NOT NULL,
    pct_target numeric NOT NULL,
    value_target numeric NOT NULL,
    id_subarea integer NOT NULL
);


ALTER TABLE public.t_sales_target_subarea OWNER TO prod_kelava;

--
-- Name: t_sales_target_subarea_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_sales_target_subarea_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_sales_target_subarea_id_seq OWNER TO prod_kelava;

--
-- Name: t_sales_target_subarea_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_sales_target_subarea_id_seq OWNED BY public.t_sales_target_subarea.id;


--
-- Name: t_spg_result_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_spg_result_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_spg_result_id_seq OWNER TO prod_kelava;

--
-- Name: t_spg_result; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_spg_result (
    id integer DEFAULT nextval('public.t_spg_result_id_seq'::regclass) NOT NULL,
    id_outlet integer NOT NULL,
    id_user integer NOT NULL,
    feedback character varying(256) NOT NULL,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT (now() + '00:00:00'::interval) NOT NULL,
    remarks character varying(256)
);


ALTER TABLE public.t_spg_result OWNER TO prod_kelava;

--
-- Name: t_visit_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_visit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_visit_id_seq OWNER TO prod_kelava;

--
-- Name: t_visit; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_visit (
    id integer DEFAULT nextval('public.t_visit_id_seq'::regclass) NOT NULL,
    id_user integer NOT NULL,
    id_road_plan integer,
    check_in timestamp with time zone,
    check_out timestamp with time zone,
    remarks character varying(256),
    meta_data json,
    id_customer_outlet integer,
    latitude numeric,
    longitude numeric,
    created_by integer NOT NULL,
    created_date timestamp with time zone DEFAULT now() NOT NULL,
    id_client integer NOT NULL,
    id_customer integer,
    realization_date date,
    id_outlet integer
);


ALTER TABLE public.t_visit OWNER TO prod_kelava;

--
-- Name: t_visit_data_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_visit_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_visit_data_id_seq OWNER TO prod_kelava;

--
-- Name: t_visit_data; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_visit_data (
    id integer DEFAULT nextval('public.t_visit_data_id_seq'::regclass) NOT NULL,
    temperature numeric NOT NULL,
    kerusakan character varying(256),
    foto_display character varying(256) NOT NULL,
    foto_kompetitor character varying(256),
    status_pengunjung character varying(256) NOT NULL,
    status_display character varying(256) NOT NULL,
    remarks character varying(256),
    id_visit integer NOT NULL,
    foto_pengunjung character varying,
    id_client integer
);


ALTER TABLE public.t_visit_data OWNER TO prod_kelava;

--
-- Name: t_visit_product_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_visit_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE public.t_visit_product_id_seq OWNER TO prod_kelava;

--
-- Name: t_visit_product; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_visit_product (
    id integer DEFAULT nextval('public.t_visit_product_id_seq'::regclass) NOT NULL,
    id_visit integer NOT NULL,
    qty numeric NOT NULL,
    id_product integer NOT NULL,
    percentage character varying,
    id_client integer
);


ALTER TABLE public.t_visit_product OWNER TO prod_kelava;

--
-- Name: t_withdraw; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_withdraw (
    id integer NOT NULL,
    withdraw_date date NOT NULL,
    amount numeric,
    created_date timestamp with time zone DEFAULT now() NOT NULL,
    status character varying(256) DEFAULT 'Open'::character varying NOT NULL,
    image_url text,
    updated_by integer,
    updated_date timestamp with time zone,
    client_code character varying(256) NOT NULL,
    created_by integer NOT NULL,
    created_by_name character varying(256) NOT NULL,
    withdraw_no character varying(256) DEFAULT '1'::character varying NOT NULL
);


ALTER TABLE public.t_withdraw OWNER TO prod_kelava;

--
-- Name: t_withdraw_funds_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_withdraw_funds_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_withdraw_funds_id_seq OWNER TO prod_kelava;

--
-- Name: t_withdraw_funds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_withdraw_funds_id_seq OWNED BY public.t_withdraw.id;


--
-- Name: t_withdraw_line; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.t_withdraw_line (
    id integer NOT NULL,
    id_withdraw integer NOT NULL,
    sales_order_number character varying(256) NOT NULL,
    amount numeric NOT NULL
);


ALTER TABLE public.t_withdraw_line OWNER TO prod_kelava;

--
-- Name: t_withdraw_lin_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.t_withdraw_lin_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.t_withdraw_lin_id_seq OWNER TO prod_kelava;

--
-- Name: t_withdraw_lin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.t_withdraw_lin_id_seq OWNED BY public.t_withdraw_line.id;


--
-- Name: temp; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.temp (
    text json NOT NULL,
    date timestamp with time zone DEFAULT now()
);


ALTER TABLE public.temp OWNER TO prod_kelava;

--
-- Name: v_dashboard_contract; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_dashboard_contract AS
 SELECT sum(
        CASE
            WHEN (mca.id_contract IS NULL) THEN 1
            ELSE 0
        END) AS pending,
    sum(
        CASE
            WHEN ((mca.id_contract IS NOT NULL) AND ((mca.status)::text = 'Approved'::text)) THEN 1
            ELSE 0
        END) AS approved
   FROM (public.m_contract mc
     LEFT JOIN public.m_contract_approval mca ON ((mca.id_contract = mc.id)));


ALTER TABLE public.v_dashboard_contract OWNER TO prod_kelava;

--
-- Name: v_dashboard_event; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_dashboard_event AS
 SELECT te.id,
    te.location,
    te.start_date,
    te.remarks,
    te.target,
    te.contact_person_name,
    te.contact_person_phone,
    te.created_by,
    te.created_date,
    te.end_date,
    te.title,
    tep.id_user AS id_pic,
    'Ongoing'::text AS status
   FROM ((public.t_event te
     LEFT JOIN public.t_event_result ter ON ((ter.id_event = te.id)))
     JOIN public.t_event_pic tep ON ((tep.id_event = te.id)))
  WHERE ((ter.id IS NULL) AND (to_char((te.start_date)::timestamp with time zone, 'YYYY-mm-dd'::text) <= to_char(now(), 'YYYY-mm-dd'::text)) AND (to_char((te.end_date)::timestamp with time zone, 'YYYY-mm-dd'::text) >= to_char(now(), 'YYYY-mm-dd'::text)))
UNION
 SELECT te.id,
    te.location,
    te.start_date,
    te.remarks,
    te.target,
    te.contact_person_name,
    te.contact_person_phone,
    te.created_by,
    te.created_date,
    te.end_date,
    te.title,
    tep.id_user AS id_pic,
    'Coming Soon'::text AS status
   FROM ((public.t_event te
     LEFT JOIN public.t_event_result ter ON ((ter.id_event = te.id)))
     JOIN public.t_event_pic tep ON ((tep.id_event = te.id)))
  WHERE ((ter.id IS NULL) AND (to_char((te.start_date)::timestamp with time zone, 'YYYY-mm-dd'::text) > to_char(now(), 'YYYY-mm-dd'::text)) AND (to_char((te.start_date)::timestamp with time zone, 'YYYY-mm-dd'::text) <= to_char((now() + '7 days'::interval day), 'YYYY-mm-dd'::text)));


ALTER TABLE public.v_dashboard_event OWNER TO prod_kelava;

--
-- Name: v_dashboard_manager_target; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_dashboard_manager_target AS
 SELECT (tstc.year)::text AS year,
    (
        CASE tstm.month
            WHEN 'Januari'::text THEN '01'::text
            WHEN 'Februari'::text THEN '02'::text
            WHEN 'Maret'::text THEN '03'::text
            WHEN 'April'::text THEN '04'::text
            WHEN 'Mei'::text THEN '05'::text
            WHEN 'Juni'::text THEN '06'::text
            WHEN 'Juli'::text THEN '07'::text
            WHEN 'Agustus'::text THEN '08'::text
            WHEN 'September'::text THEN '09'::text
            WHEN 'Oktober'::text THEN '10'::text
            WHEN 'November'::text THEN '11'::text
            WHEN 'Desember'::text THEN '12'::text
            ELSE NULL::text
        END)::character varying(256) AS month,
    sum(tstm.value_target) AS value_target
   FROM (public.t_sales_target_month tstm
     JOIN public.t_sales_target_company tstc ON ((tstm.id_target_company = tstc.id)))
  GROUP BY tstc.year, tstm.month;


ALTER TABLE public.v_dashboard_manager_target OWNER TO prod_kelava;

--
-- Name: v_dashboard_road_plan; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_dashboard_road_plan AS
 SELECT sum(
        CASE
            WHEN (trpa.id IS NULL) THEN 1
            ELSE 0
        END) AS pending,
    sum(
        CASE
            WHEN ((trpa.status)::text = 'Approved'::text) THEN 1
            ELSE 0
        END) AS approved
   FROM (public.t_road_plan trp
     LEFT JOIN public.t_road_plan_approval trpa ON ((trp.id_approval = trpa.id)));


ALTER TABLE public.v_dashboard_road_plan OWNER TO prod_kelava;

--
-- Name: v_dashboard_sales_achievement; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_dashboard_sales_achievement AS
 SELECT to_char(t_sales_order.created_date, 'YYYY'::text) AS year,
    to_char(t_sales_order.created_date, 'MM'::text) AS month,
    t_sales_order.created_by AS id_user,
    sum(t_sales_order.grand_total) AS achievement
   FROM public.t_sales_order
  GROUP BY t_sales_order.created_by, (to_char(t_sales_order.created_date, 'YYYY'::text)), (to_char(t_sales_order.created_date, 'MM'::text));


ALTER TABLE public.v_dashboard_sales_achievement OWNER TO prod_kelava;

--
-- Name: v_dashboard_sales_target; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_dashboard_sales_target AS
 SELECT (tc.year)::text AS year,
    (
        CASE tm.month
            WHEN 'Januari'::text THEN '01'::text
            WHEN 'Februari'::text THEN '02'::text
            WHEN 'Maret'::text THEN '03'::text
            WHEN 'April'::text THEN '04'::text
            WHEN 'Mei'::text THEN '05'::text
            WHEN 'Juni'::text THEN '06'::text
            WHEN 'Juli'::text THEN '07'::text
            WHEN 'Agustus'::text THEN '08'::text
            WHEN 'September'::text THEN '09'::text
            WHEN 'Oktober'::text THEN '10'::text
            WHEN 'November'::text THEN '11'::text
            WHEN 'Desember'::text THEN '12'::text
            ELSE NULL::text
        END)::character varying(256) AS month,
    t.id_user,
    sum(t.value_target) AS value_target,
    sum(t.deviasi_target) AS deviasi_target
   FROM (((((public.t_sales_target_salesman t
     JOIN public.t_sales_target_segment tts ON ((tts.id = t.id_target_segment)))
     JOIN public.t_sales_target_subarea tsa ON ((tsa.id = tts.id_target_subarea)))
     JOIN public.t_sales_target_area tta ON ((tta.id = tsa.id_target_area)))
     JOIN public.t_sales_target_month tm ON ((tm.id = tta.id_target_month)))
     JOIN public.t_sales_target_company tc ON ((tc.id = tm.id_target_company)))
  GROUP BY tc.year, tm.month, t.id_user;


ALTER TABLE public.v_dashboard_sales_target OWNER TO prod_kelava;

--
-- Name: v_event; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_event AS
 SELECT DISTINCT te.id,
    te.location,
    te.start_date,
    te.remarks,
    te.target,
    te.contact_person_name,
    te.contact_person_phone,
    te.created_by,
    te.created_date,
    te.end_date,
    te.title,
        CASE
            WHEN (ter.id IS NULL) THEN 'Pending'::text
            ELSE 'Done'::text
        END AS status,
    tep.id_user AS id_pic
   FROM ((public.t_event te
     LEFT JOIN public.t_event_result ter ON ((ter.id_event = te.id)))
     JOIN public.t_event_pic tep ON ((tep.id_event = te.id)));


ALTER TABLE public.v_event OWNER TO prod_kelava;

--
-- Name: v_event_marketing; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_event_marketing AS
 SELECT DISTINCT te.id,
    te.location,
    te.start_date,
    te.remarks,
    te.target,
    te.contact_person_name,
    te.contact_person_phone,
    te.created_by,
    te.created_date,
    te.end_date,
    te.title,
        CASE
            WHEN (ter.id IS NULL) THEN 'Pending'::text
            ELSE 'Done'::text
        END AS status
   FROM (public.t_event te
     LEFT JOIN public.t_event_result ter ON ((ter.id_event = te.id)));


ALTER TABLE public.v_event_marketing OWNER TO prod_kelava;

--
-- Name: v_helper_delivery; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_helper_delivery AS
 WITH item AS (
         SELECT sl.id_sales_order,
            sl.id_product,
            sum(sl.qty) AS qty
           FROM public.t_sales_order_line sl
          GROUP BY sl.id_sales_order, sl.id_product, sl.discount
        ), itemdelivery AS (
         SELECT d.id_sales_order,
            di.id_product,
            sum(di.qty) AS qty
           FROM (public.t_sales_order_delivery_item di
             JOIN public.t_sales_order_delivery d ON ((d.id = di.id_delivery)))
          GROUP BY d.id_sales_order, di.id_product
        )
 SELECT i.id_sales_order,
    i.id_product,
    mp.name,
    mpc.category AS group_name,
    (i.qty)::integer AS "order",
    COALESCE(id.qty, (0)::bigint) AS delivery,
    ((i.qty - (COALESCE(id.qty, (0)::bigint))::numeric))::integer AS undelivered
   FROM (((item i
     JOIN public.m_product mp ON ((mp.id = i.id_product)))
     JOIN public.m_product_category mpc ON ((mpc.id = mp.id_category)))
     LEFT JOIN itemdelivery id ON (((i.id_product = id.id_product) AND (i.id_sales_order = id.id_sales_order))))
  ORDER BY i.id_product;


ALTER TABLE public.v_helper_delivery OWNER TO prod_kelava;

--
-- Name: v_sales_order_by_customer; Type: VIEW; Schema: public; Owner: prod_kelava
--

CREATE VIEW public.v_sales_order_by_customer AS
 SELECT date_part('year'::text, t_sales_order.sales_order_date) AS year,
    to_char((t_sales_order.sales_order_date)::timestamp with time zone, 'MM'::text) AS month,
    t_sales_order.id_customer,
    count(1) AS count,
    max((p_user.fullname)::text) AS sales
   FROM (public.t_sales_order
     LEFT JOIN public.p_user ON ((t_sales_order.created_by = p_user.id)))
  GROUP BY (date_part('year'::text, t_sales_order.sales_order_date)), (to_char((t_sales_order.sales_order_date)::timestamp with time zone, 'MM'::text)), t_sales_order.id_customer;


ALTER TABLE public.v_sales_order_by_customer OWNER TO prod_kelava;

--
-- Name: x_setting_application; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.x_setting_application (
    id integer NOT NULL,
    name character varying(256) NOT NULL,
    value text NOT NULL
);


ALTER TABLE public.x_setting_application OWNER TO prod_kelava;

--
-- Name: x_setting_application_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.x_setting_application_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.x_setting_application_id_seq OWNER TO prod_kelava;

--
-- Name: x_setting_application_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.x_setting_application_id_seq OWNED BY public.x_setting_application.id;


--
-- Name: x_token_application; Type: TABLE; Schema: public; Owner: prod_kelava
--

CREATE TABLE public.x_token_application (
    id integer NOT NULL,
    app_name character varying(256) NOT NULL,
    token text NOT NULL,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    id_client integer,
    id_user integer
);


ALTER TABLE public.x_token_application OWNER TO prod_kelava;

--
-- Name: x_token_application_id_seq; Type: SEQUENCE; Schema: public; Owner: prod_kelava
--

CREATE SEQUENCE public.x_token_application_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.x_token_application_id_seq OWNER TO prod_kelava;

--
-- Name: x_token_application_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prod_kelava
--

ALTER SEQUENCE public.x_token_application_id_seq OWNED BY public.x_token_application.id;


--
-- Name: remote_schemas id; Type: DEFAULT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.remote_schemas ALTER COLUMN id SET DEFAULT nextval('hdb_catalog.remote_schemas_id_seq'::regclass);


--
-- Name: i_withdraw id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.i_withdraw ALTER COLUMN id SET DEFAULT nextval('public.i_withdraw_id_seq'::regclass);


--
-- Name: i_withdraw_line id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.i_withdraw_line ALTER COLUMN id SET DEFAULT nextval('public.i_withdraw_line_id_seq'::regclass);


--
-- Name: m_add_on id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_add_on ALTER COLUMN id SET DEFAULT nextval('public.m_add_on_id_seq'::regclass);


--
-- Name: m_add_on_client id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_add_on_client ALTER COLUMN id SET DEFAULT nextval('public.m_add_on_client_id_seq'::regclass);


--
-- Name: m_channel_pembayaran id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_channel_pembayaran ALTER COLUMN id SET DEFAULT nextval('public.m_channel_pembayaran_id_seq'::regclass);


--
-- Name: m_charges id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_charges ALTER COLUMN id SET DEFAULT nextval('public.m_charges_id_seq'::regclass);


--
-- Name: m_client id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_client ALTER COLUMN id SET DEFAULT nextval('public.m_client_id_seq'::regclass);


--
-- Name: m_client_packages id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_client_packages ALTER COLUMN id SET DEFAULT nextval('public.m_client_packages_id_seq'::regclass);


--
-- Name: m_client_payment id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_client_payment ALTER COLUMN id SET DEFAULT nextval('public.m_client_payment_id_seq'::regclass);


--
-- Name: m_contact id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contact ALTER COLUMN id SET DEFAULT nextval('public.m_customer_contact_id_seq'::regclass);


--
-- Name: m_customer_contact id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_contact ALTER COLUMN id SET DEFAULT nextval('public.m_customer_contact_id_seq1'::regclass);


--
-- Name: m_customer_devices id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_customer_devices ALTER COLUMN id SET DEFAULT nextval('public.m_customer_devices_id_seq'::regclass);


--
-- Name: m_customer_group id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_customer_group ALTER COLUMN id SET DEFAULT nextval('public.t_customer_group_id_seq'::regclass);


--
-- Name: m_customer_social_media id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_social_media ALTER COLUMN id SET DEFAULT nextval('public.m_customer_social_media_id_seq'::regclass);


--
-- Name: m_knowledge id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_knowledge ALTER COLUMN id SET DEFAULT nextval('public.m_knowledge_id_seq'::regclass);


--
-- Name: m_membership_client id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_client ALTER COLUMN id SET DEFAULT nextval('public.t_membership_client_id_seq'::regclass);


--
-- Name: m_membership_customer id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_customer ALTER COLUMN id SET DEFAULT nextval('public.m_membership_customer_id_seq'::regclass);


--
-- Name: m_membership_level id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_level ALTER COLUMN id SET DEFAULT nextval('public.m_membership_level_id_seq'::regclass);


--
-- Name: m_membership_type id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_type ALTER COLUMN id SET DEFAULT nextval('public.m_membership_type_id_seq'::regclass);


--
-- Name: m_opportunity_stage id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_opportunity_stage ALTER COLUMN id SET DEFAULT nextval('public.m_opportunity_stage_id_seq'::regclass);


--
-- Name: m_outlet id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_id_seq'::regclass);


--
-- Name: m_outlet_complement id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_complement_id_seq'::regclass);


--
-- Name: m_outlet_complement_new id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement_new ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_complement_new_id_seq'::regclass);


--
-- Name: m_outlet_complement_price id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement_price ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_complement_price_id_seq'::regclass);


--
-- Name: m_outlet_complement_price_new id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_complement_price_new ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_complement_price_new_id_seq'::regclass);


--
-- Name: m_outlet_has_channel_pembayaran id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_has_channel_pembayaran ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_has_channel_pembayaran_id_seq'::regclass);


--
-- Name: m_outlet_pic id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_pic ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_pic_id_seq'::regclass);


--
-- Name: m_outlet_queue_ads id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_queue_ads ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_queue_ads_id_seq'::regclass);


--
-- Name: m_outlet_setting id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_setting ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_setting_id_seq'::regclass);


--
-- Name: m_outlet_setting_value id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_setting_value ALTER COLUMN id SET DEFAULT nextval('public.m_outlet_setting_value_id_seq'::regclass);


--
-- Name: m_package id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_package ALTER COLUMN id SET DEFAULT nextval('public.m_package_id_seq'::regclass);


--
-- Name: m_package_conf id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_package_conf ALTER COLUMN id SET DEFAULT nextval('public.m_package_conf_id_seq'::regclass);


--
-- Name: m_product_bom id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_bom ALTER COLUMN id SET DEFAULT nextval('public.m_product_bom_id_seq'::regclass);


--
-- Name: m_product_bomdetail id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_bomdetail ALTER COLUMN id SET DEFAULT nextval('public.m_product_bomdetail_id_seq'::regclass);


--
-- Name: m_product_complement id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_complement ALTER COLUMN id SET DEFAULT nextval('public.m_product_complement_id_seq'::regclass);


--
-- Name: m_product_complement_new id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_complement_new ALTER COLUMN id SET DEFAULT nextval('public.m_product_complement_id_seq1'::regclass);


--
-- Name: m_product_material id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_material ALTER COLUMN id SET DEFAULT nextval('public.m_product_material_id_seq'::regclass);


--
-- Name: m_product_outlet id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet ALTER COLUMN id SET DEFAULT nextval('public.m_product_outlet_id_seq'::regclass);


--
-- Name: m_product_outlet_customer_group id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_outlet_customer_group ALTER COLUMN id SET DEFAULT nextval('public.m_product_outlet_customer_group_id_seq'::regclass);


--
-- Name: m_product_outlet_price id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet_price ALTER COLUMN id SET DEFAULT nextval('public.m_product_outlet_price_id_seq'::regclass);


--
-- Name: m_product_subcategory id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_subcategory ALTER COLUMN id SET DEFAULT nextval('public.m_product_subcategory_id_seq'::regclass);


--
-- Name: m_product_type id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_type ALTER COLUMN id SET DEFAULT nextval('public.m_product_type_id_seq'::regclass);


--
-- Name: m_product_unit id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_unit ALTER COLUMN id SET DEFAULT nextval('public.m_product_unit_id_seq'::regclass);


--
-- Name: m_setting id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_setting ALTER COLUMN id SET DEFAULT nextval('public.m_setting_id_seq'::regclass);


--
-- Name: m_setting_value id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_setting_value ALTER COLUMN id SET DEFAULT nextval('public.m_setting_value_id_seq'::regclass);


--
-- Name: m_sosmed id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_sosmed ALTER COLUMN id SET DEFAULT nextval('public.m_sosmed_id_seq'::regclass);


--
-- Name: m_totem id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_totem ALTER COLUMN id SET DEFAULT nextval('public.m_totem_id_seq'::regclass);


--
-- Name: m_visit_field1 id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_visit_field1 ALTER COLUMN id SET DEFAULT nextval('public.m_field1_id_seq'::regclass);


--
-- Name: m_visit_field2 id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_visit_field2 ALTER COLUMN id SET DEFAULT nextval('public.m_visit_field2_id_seq'::regclass);


--
-- Name: m_visit_field3 id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_visit_field3 ALTER COLUMN id SET DEFAULT nextval('public.m_visit_field3_id_seq'::regclass);


--
-- Name: p_request_reset_password id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.p_request_reset_password ALTER COLUMN id SET DEFAULT nextval('public.p_request_reset_password_id_seq'::regclass);


--
-- Name: s_pos id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.s_pos ALTER COLUMN id SET DEFAULT nextval('public.s_pos_id_seq'::regclass);


--
-- Name: t_customer_poin id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_customer_poin ALTER COLUMN id SET DEFAULT nextval('public.t_customer_poin_id_seq'::regclass);


--
-- Name: t_event_pic id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_pic ALTER COLUMN id SET DEFAULT nextval('public.t_event_pic_id_seq'::regclass);


--
-- Name: t_hit id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_hit ALTER COLUMN id SET DEFAULT nextval('public.t_hit_id_seq'::regclass);


--
-- Name: t_invoice id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_invoice ALTER COLUMN id SET DEFAULT nextval('public.t_invoice_id_seq'::regclass);


--
-- Name: t_log_payment_gateway id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_log_payment_gateway ALTER COLUMN id SET DEFAULT nextval('public.t_log_payment_gateway_id_seq'::regclass);


--
-- Name: t_news id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_news ALTER COLUMN id SET DEFAULT nextval('public.t_news_id_seq'::regclass);


--
-- Name: t_opportunity id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity ALTER COLUMN id SET DEFAULT nextval('public.t_opportunity_id_seq'::regclass);


--
-- Name: t_opportunity_file id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity_file ALTER COLUMN id SET DEFAULT nextval('public.t_opportunity_file_id_seq'::regclass);


--
-- Name: t_opportunity_timeline id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity_timeline ALTER COLUMN id SET DEFAULT nextval('public.t_opportunity_timeline_id_seq'::regclass);


--
-- Name: t_otp_log id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_otp_log ALTER COLUMN id SET DEFAULT nextval('public.t_otp_log_id_seq'::regclass);


--
-- Name: t_outlet_charges id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_outlet_charges ALTER COLUMN id SET DEFAULT nextval('public.t_outlet_charges_id_seq'::regclass);


--
-- Name: t_outlet_charges_value id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_outlet_charges_value ALTER COLUMN id SET DEFAULT nextval('public.t_outlet_charges_value_id_seq'::regclass);


--
-- Name: t_outlet_promo id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_outlet_promo ALTER COLUMN id SET DEFAULT nextval('public.t_outlet_promo_id_seq'::regclass);


--
-- Name: t_outlet_queue_date_number id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_outlet_queue_date_number ALTER COLUMN id SET DEFAULT nextval('public.t_outlet_queue_date_number_id_seq'::regclass);


--
-- Name: t_payment id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_payment ALTER COLUMN id SET DEFAULT nextval('public.t_payment_id_seq'::regclass);


--
-- Name: t_payment_callback_response id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_payment_callback_response ALTER COLUMN id SET DEFAULT nextval('public.t_payment_callback_response_id_seq'::regclass);


--
-- Name: t_product_outlet_movement id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_product_outlet_movement ALTER COLUMN id SET DEFAULT nextval('public.t_product_materialoutlet_id_seq'::regclass);


--
-- Name: t_product_outlet_stock id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_product_outlet_stock ALTER COLUMN id SET DEFAULT nextval('public.t_product_outlet_stock_id_seq'::regclass);


--
-- Name: t_promo id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_promo ALTER COLUMN id SET DEFAULT nextval('public.t_promo_id_seq'::regclass);


--
-- Name: t_purchase_order id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_purchase_order ALTER COLUMN id SET DEFAULT nextval('public.t_purchase_order_id_seq'::regclass);


--
-- Name: t_registration id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_registration ALTER COLUMN id SET DEFAULT nextval('public.t_registration_id_seq'::regclass);


--
-- Name: t_sales_order_delivery id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery ALTER COLUMN id SET DEFAULT nextval('public.t_sales_order_delivery_id_seq'::regclass);


--
-- Name: t_sales_order_delivery_item id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item ALTER COLUMN id SET DEFAULT nextval('public.t_sales_order_delivery_item_id_seq'::regclass);


--
-- Name: t_sales_order_delivery_item_status id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item_status ALTER COLUMN id SET DEFAULT nextval('public.t_sales_order_delivery_item_status_id_seq'::regclass);


--
-- Name: t_sales_order_status_history id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_status_history ALTER COLUMN id SET DEFAULT nextval('public.t_sales_order_status_history_id_seq'::regclass);


--
-- Name: t_sales_target_area id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_area ALTER COLUMN id SET DEFAULT nextval('public.t_sales_target_area_id_seq'::regclass);


--
-- Name: t_sales_target_month id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_month ALTER COLUMN id SET DEFAULT nextval('public.t_sales_target_month_id_seq'::regclass);


--
-- Name: t_sales_target_product id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_product ALTER COLUMN id SET DEFAULT nextval('public.t_sales_target_product_id_seq'::regclass);


--
-- Name: t_sales_target_salesman id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_salesman ALTER COLUMN id SET DEFAULT nextval('public.t_sales_target_salesman_id_seq'::regclass);


--
-- Name: t_sales_target_segment id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_segment ALTER COLUMN id SET DEFAULT nextval('public.t_sales_target_segment_id_seq'::regclass);


--
-- Name: t_sales_target_store id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_store ALTER COLUMN id SET DEFAULT nextval('public.t_sales_target_store_id_seq'::regclass);


--
-- Name: t_sales_target_subarea id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_subarea ALTER COLUMN id SET DEFAULT nextval('public.t_sales_target_subarea_id_seq'::regclass);


--
-- Name: t_withdraw id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_withdraw ALTER COLUMN id SET DEFAULT nextval('public.t_withdraw_funds_id_seq'::regclass);


--
-- Name: t_withdraw_line id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_withdraw_line ALTER COLUMN id SET DEFAULT nextval('public.t_withdraw_lin_id_seq'::regclass);


--
-- Name: x_setting_application id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.x_setting_application ALTER COLUMN id SET DEFAULT nextval('public.x_setting_application_id_seq'::regclass);


--
-- Name: x_token_application id; Type: DEFAULT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.x_token_application ALTER COLUMN id SET DEFAULT nextval('public.x_token_application_id_seq'::regclass);


--
-- Name: event_triggers event_triggers_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.event_triggers
    ADD CONSTRAINT event_triggers_pkey PRIMARY KEY (name);


--
-- Name: hdb_action_permission hdb_action_permission_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_action_permission
    ADD CONSTRAINT hdb_action_permission_pkey PRIMARY KEY (action_name, role_name);


--
-- Name: hdb_action hdb_action_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_action
    ADD CONSTRAINT hdb_action_pkey PRIMARY KEY (action_name);


--
-- Name: hdb_allowlist hdb_allowlist_collection_name_key; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_allowlist
    ADD CONSTRAINT hdb_allowlist_collection_name_key UNIQUE (collection_name);


--
-- Name: hdb_computed_field hdb_computed_field_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_computed_field
    ADD CONSTRAINT hdb_computed_field_pkey PRIMARY KEY (table_schema, table_name, computed_field_name);


--
-- Name: hdb_cron_triggers hdb_cron_triggers_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_cron_triggers
    ADD CONSTRAINT hdb_cron_triggers_pkey PRIMARY KEY (name);


--
-- Name: hdb_function hdb_function_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_function
    ADD CONSTRAINT hdb_function_pkey PRIMARY KEY (function_schema, function_name);


--
-- Name: hdb_permission hdb_permission_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_permission
    ADD CONSTRAINT hdb_permission_pkey PRIMARY KEY (table_schema, table_name, role_name, perm_type);


--
-- Name: hdb_query_collection hdb_query_collection_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_query_collection
    ADD CONSTRAINT hdb_query_collection_pkey PRIMARY KEY (collection_name);


--
-- Name: hdb_relationship hdb_relationship_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_relationship
    ADD CONSTRAINT hdb_relationship_pkey PRIMARY KEY (table_schema, table_name, rel_name);


--
-- Name: hdb_remote_relationship hdb_remote_relationship_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_remote_relationship
    ADD CONSTRAINT hdb_remote_relationship_pkey PRIMARY KEY (remote_relationship_name, table_schema, table_name);


--
-- Name: hdb_table hdb_table_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_table
    ADD CONSTRAINT hdb_table_pkey PRIMARY KEY (table_schema, table_name);


--
-- Name: remote_schemas remote_schemas_name_key; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.remote_schemas
    ADD CONSTRAINT remote_schemas_name_key UNIQUE (name);


--
-- Name: remote_schemas remote_schemas_pkey; Type: CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.remote_schemas
    ADD CONSTRAINT remote_schemas_pkey PRIMARY KEY (id);


--
-- Name: t_event event_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event
    ADD CONSTRAINT event_id PRIMARY KEY (id);


--
-- Name: i_withdraw i_withdraw_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.i_withdraw
    ADD CONSTRAINT i_withdraw_id PRIMARY KEY (id);


--
-- Name: i_withdraw_line i_withdraw_line_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.i_withdraw_line
    ADD CONSTRAINT i_withdraw_line_id PRIMARY KEY (id);


--
-- Name: m_add_on_client m_add_on_client_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_add_on_client
    ADD CONSTRAINT m_add_on_client_id PRIMARY KEY (id);


--
-- Name: m_add_on m_add_on_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_add_on
    ADD CONSTRAINT m_add_on_id PRIMARY KEY (id);


--
-- Name: m_area m_area_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_area
    ADD CONSTRAINT m_area_id PRIMARY KEY (id);


--
-- Name: m_channel_pembayaran m_channel_pembayaran_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_channel_pembayaran
    ADD CONSTRAINT m_channel_pembayaran_id PRIMARY KEY (id);


--
-- Name: m_charges m_charges_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_charges
    ADD CONSTRAINT m_charges_id PRIMARY KEY (id);


--
-- Name: m_city m_city_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_city
    ADD CONSTRAINT m_city_id PRIMARY KEY (id);


--
-- Name: m_client m_client_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_client
    ADD CONSTRAINT m_client_id PRIMARY KEY (id);


--
-- Name: m_client_packages m_client_packages_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_client_packages
    ADD CONSTRAINT m_client_packages_id PRIMARY KEY (id);


--
-- Name: m_client_payment m_client_payment_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_client_payment
    ADD CONSTRAINT m_client_payment_id PRIMARY KEY (id);


--
-- Name: m_contract_approval m_contract_approval_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contract_approval
    ADD CONSTRAINT m_contract_approval_id PRIMARY KEY (id);


--
-- Name: m_contract m_contract_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contract
    ADD CONSTRAINT m_contract_id PRIMARY KEY (id);


--
-- Name: m_contract_price m_contract_price_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contract_price
    ADD CONSTRAINT m_contract_price_id PRIMARY KEY (id);


--
-- Name: m_country m_country_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_country
    ADD CONSTRAINT m_country_id PRIMARY KEY (id);


--
-- Name: m_contact m_customer_contact_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contact
    ADD CONSTRAINT m_customer_contact_id PRIMARY KEY (id);


--
-- Name: m_customer_contact m_customer_contact_id2; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_contact
    ADD CONSTRAINT m_customer_contact_id2 PRIMARY KEY (id);


--
-- Name: m_customer_devices m_customer_devices_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_customer_devices
    ADD CONSTRAINT m_customer_devices_id PRIMARY KEY (id);


--
-- Name: m_customer m_customer_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer
    ADD CONSTRAINT m_customer_id PRIMARY KEY (id);


--
-- Name: m_customer_outlet m_customer_outlet_code; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_code UNIQUE (code);


--
-- Name: m_customer_outlet m_customer_outlet_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_id PRIMARY KEY (id);


--
-- Name: m_customer_segment m_customer_segment_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_segment
    ADD CONSTRAINT m_customer_segment_id PRIMARY KEY (id);


--
-- Name: m_customer_social_media m_customer_social_media_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_social_media
    ADD CONSTRAINT m_customer_social_media_id PRIMARY KEY (id);


--
-- Name: m_visit_field1 m_field1_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_visit_field1
    ADD CONSTRAINT m_field1_id PRIMARY KEY (id);


--
-- Name: m_hardware m_hardware_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_hardware
    ADD CONSTRAINT m_hardware_id PRIMARY KEY (id);


--
-- Name: m_knowledge m_knowledge_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_knowledge
    ADD CONSTRAINT m_knowledge_id PRIMARY KEY (id);


--
-- Name: m_membership_customer m_membership_customer_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_customer
    ADD CONSTRAINT m_membership_customer_id PRIMARY KEY (id);


--
-- Name: m_membership_level m_membership_level_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_level
    ADD CONSTRAINT m_membership_level_id PRIMARY KEY (id);


--
-- Name: m_membership_type m_membership_type_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_type
    ADD CONSTRAINT m_membership_type_id PRIMARY KEY (id);


--
-- Name: m_opportunity_stage m_opportunity_stage_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_opportunity_stage
    ADD CONSTRAINT m_opportunity_stage_id PRIMARY KEY (id);


--
-- Name: m_outlet_complement m_outlet_complement_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement
    ADD CONSTRAINT m_outlet_complement_id PRIMARY KEY (id);


--
-- Name: m_outlet_complement_new m_outlet_complement_new_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement_new
    ADD CONSTRAINT m_outlet_complement_new_id PRIMARY KEY (id);


--
-- Name: m_outlet_complement_price m_outlet_complement_price_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement_price
    ADD CONSTRAINT m_outlet_complement_price_id PRIMARY KEY (id);


--
-- Name: m_outlet_complement_price_new m_outlet_complement_price_new_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_complement_price_new
    ADD CONSTRAINT m_outlet_complement_price_new_id PRIMARY KEY (id);


--
-- Name: m_outlet_has_channel_pembayaran m_outlet_has_channel_pembayaran_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_has_channel_pembayaran
    ADD CONSTRAINT m_outlet_has_channel_pembayaran_id PRIMARY KEY (id);


--
-- Name: m_outlet m_outlet_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet
    ADD CONSTRAINT m_outlet_id PRIMARY KEY (id);


--
-- Name: m_outlet_pic m_outlet_pic_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_pic
    ADD CONSTRAINT m_outlet_pic_id PRIMARY KEY (id);


--
-- Name: m_outlet_queue_ads m_outlet_queue_ads_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_queue_ads
    ADD CONSTRAINT m_outlet_queue_ads_id PRIMARY KEY (id);


--
-- Name: m_outlet_setting m_outlet_setting_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_setting
    ADD CONSTRAINT m_outlet_setting_id PRIMARY KEY (id);


--
-- Name: m_outlet_setting_value m_outlet_setting_value_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_setting_value
    ADD CONSTRAINT m_outlet_setting_value_id PRIMARY KEY (id);


--
-- Name: m_package_conf m_package_conf_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_package_conf
    ADD CONSTRAINT m_package_conf_id PRIMARY KEY (id);


--
-- Name: m_package m_package_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_package
    ADD CONSTRAINT m_package_id PRIMARY KEY (id);


--
-- Name: m_product_bom m_product_bom_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_bom
    ADD CONSTRAINT m_product_bom_id PRIMARY KEY (id);


--
-- Name: m_product_bomdetail m_product_bomdetail_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_bomdetail
    ADD CONSTRAINT m_product_bomdetail_id PRIMARY KEY (id);


--
-- Name: m_product_brand m_product_brand_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_brand
    ADD CONSTRAINT m_product_brand_id PRIMARY KEY (id);


--
-- Name: m_product_category m_product_category_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_category
    ADD CONSTRAINT m_product_category_id PRIMARY KEY (id);


--
-- Name: m_product_complement m_product_complement_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_complement
    ADD CONSTRAINT m_product_complement_id PRIMARY KEY (id);


--
-- Name: m_product_complement_new m_product_complement_id_new; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_complement_new
    ADD CONSTRAINT m_product_complement_id_new PRIMARY KEY (id);


--
-- Name: m_product_group m_product_group_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_group
    ADD CONSTRAINT m_product_group_id PRIMARY KEY (id);


--
-- Name: m_product m_product_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product
    ADD CONSTRAINT m_product_id PRIMARY KEY (id);


--
-- Name: m_product_material m_product_material_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_material
    ADD CONSTRAINT m_product_material_id PRIMARY KEY (id);


--
-- Name: m_product_outlet_customer_group m_product_outlet_customer_group_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_outlet_customer_group
    ADD CONSTRAINT m_product_outlet_customer_group_id PRIMARY KEY (id);


--
-- Name: m_product_outlet m_product_outlet_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet
    ADD CONSTRAINT m_product_outlet_id PRIMARY KEY (id);


--
-- Name: m_product_outlet_price m_product_outlet_price_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet_price
    ADD CONSTRAINT m_product_outlet_price_id PRIMARY KEY (id);


--
-- Name: m_product_price m_product_price_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_price
    ADD CONSTRAINT m_product_price_id PRIMARY KEY (id);


--
-- Name: m_product_subcategory m_product_subcategory_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_subcategory
    ADD CONSTRAINT m_product_subcategory_id PRIMARY KEY (id);


--
-- Name: m_product_subgroup m_product_subgroup_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_subgroup
    ADD CONSTRAINT m_product_subgroup_id PRIMARY KEY (id);


--
-- Name: m_product_type m_product_type_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_type
    ADD CONSTRAINT m_product_type_id PRIMARY KEY (id);


--
-- Name: m_product_unit m_product_unit_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_unit
    ADD CONSTRAINT m_product_unit_id PRIMARY KEY (id);


--
-- Name: m_province m_province_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_province
    ADD CONSTRAINT m_province_id PRIMARY KEY (id);


--
-- Name: m_region m_region_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_region
    ADD CONSTRAINT m_region_id PRIMARY KEY (id);


--
-- Name: m_setting m_setting_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_setting
    ADD CONSTRAINT m_setting_id PRIMARY KEY (id);


--
-- Name: m_setting_value m_setting_value_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_setting_value
    ADD CONSTRAINT m_setting_value_id PRIMARY KEY (id);


--
-- Name: m_sosmed m_sosmed_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_sosmed
    ADD CONSTRAINT m_sosmed_id PRIMARY KEY (id);


--
-- Name: m_subarea m_subarea_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_subarea
    ADD CONSTRAINT m_subarea_id PRIMARY KEY (id);


--
-- Name: m_subregion m_subregion_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_subregion
    ADD CONSTRAINT m_subregion_id PRIMARY KEY (id);


--
-- Name: m_totem m_totem_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_totem
    ADD CONSTRAINT m_totem_id PRIMARY KEY (id);


--
-- Name: m_visit_field2 m_visit_field2_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_visit_field2
    ADD CONSTRAINT m_visit_field2_id PRIMARY KEY (id);


--
-- Name: m_visit_field3 m_visit_field3_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_visit_field3
    ADD CONSTRAINT m_visit_field3_id PRIMARY KEY (id);


--
-- Name: p_migration p_migration_version; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.p_migration
    ADD CONSTRAINT p_migration_version PRIMARY KEY (version);


--
-- Name: pr_project p_project_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_project
    ADD CONSTRAINT p_project_id PRIMARY KEY (id);


--
-- Name: p_request_reset_password p_request_reset_password_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.p_request_reset_password
    ADD CONSTRAINT p_request_reset_password_id PRIMARY KEY (id);


--
-- Name: p_role p_role_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.p_role
    ADD CONSTRAINT p_role_id PRIMARY KEY (id);


--
-- Name: p_user p_user_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.p_user
    ADD CONSTRAINT p_user_id PRIMARY KEY (id);


--
-- Name: p_user_role p_user_role_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.p_user_role
    ADD CONSTRAINT p_user_role_id PRIMARY KEY (id);


--
-- Name: pr_target pr_target_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_target
    ADD CONSTRAINT pr_target_id PRIMARY KEY (id);


--
-- Name: pr_task_realization pr_task_realization_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_task_realization
    ADD CONSTRAINT pr_task_realization_id PRIMARY KEY (id);


--
-- Name: s_pos s_pos_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.s_pos
    ADD CONSTRAINT s_pos_id PRIMARY KEY (id);


--
-- Name: m_customer_group t_customer_group_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_customer_group
    ADD CONSTRAINT t_customer_group_id PRIMARY KEY (id);


--
-- Name: t_customer_poin t_customer_poin_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_customer_poin
    ADD CONSTRAINT t_customer_poin_id PRIMARY KEY (id);


--
-- Name: t_event_assign t_event_assign_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_assign
    ADD CONSTRAINT t_event_assign_id PRIMARY KEY (id);


--
-- Name: t_event_pic t_event_pic_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_pic
    ADD CONSTRAINT t_event_pic_id PRIMARY KEY (id);


--
-- Name: t_event_result t_event_result_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_result
    ADD CONSTRAINT t_event_result_id PRIMARY KEY (id);


--
-- Name: t_hardware_usage t_hardware_usage_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_hardware_usage
    ADD CONSTRAINT t_hardware_usage_id PRIMARY KEY (id);


--
-- Name: t_hit t_hit_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_hit
    ADD CONSTRAINT t_hit_id PRIMARY KEY (id);


--
-- Name: t_invoice t_invoice_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_invoice
    ADD CONSTRAINT t_invoice_id PRIMARY KEY (id);


--
-- Name: t_log_payment_gateway t_log_payment_gateway_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_log_payment_gateway
    ADD CONSTRAINT t_log_payment_gateway_id PRIMARY KEY (id);


--
-- Name: m_membership_client t_membership_client_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_client
    ADD CONSTRAINT t_membership_client_id PRIMARY KEY (id);


--
-- Name: t_news t_news_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_news
    ADD CONSTRAINT t_news_id PRIMARY KEY (id);


--
-- Name: t_opportunity_file t_opportunity_file_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity_file
    ADD CONSTRAINT t_opportunity_file_id PRIMARY KEY (id);


--
-- Name: t_opportunity t_opportunity_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity
    ADD CONSTRAINT t_opportunity_id PRIMARY KEY (id);


--
-- Name: t_opportunity_timeline t_opportunity_timeline_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity_timeline
    ADD CONSTRAINT t_opportunity_timeline_id PRIMARY KEY (id);


--
-- Name: t_otp_log t_otp_log_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_otp_log
    ADD CONSTRAINT t_otp_log_id PRIMARY KEY (id);


--
-- Name: t_outlet_charges t_outlet_charges_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_outlet_charges
    ADD CONSTRAINT t_outlet_charges_id PRIMARY KEY (id);


--
-- Name: t_outlet_charges_value t_outlet_charges_value_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_outlet_charges_value
    ADD CONSTRAINT t_outlet_charges_value_id PRIMARY KEY (id);


--
-- Name: t_outlet_promo t_outlet_promo_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_outlet_promo
    ADD CONSTRAINT t_outlet_promo_id PRIMARY KEY (id);


--
-- Name: t_outlet_queue_date t_outlet_queue_date_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_outlet_queue_date
    ADD CONSTRAINT t_outlet_queue_date_id PRIMARY KEY (id);


--
-- Name: t_outlet_queue_date_number t_outlet_queue_date_number_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_outlet_queue_date_number
    ADD CONSTRAINT t_outlet_queue_date_number_id PRIMARY KEY (id);


--
-- Name: t_payment_callback_response t_payment_callback_response_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_payment_callback_response
    ADD CONSTRAINT t_payment_callback_response_id PRIMARY KEY (id);


--
-- Name: t_payment t_payment_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_payment
    ADD CONSTRAINT t_payment_id PRIMARY KEY (id);


--
-- Name: t_product_outlet_movement t_product_materialoutlet_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_product_outlet_movement
    ADD CONSTRAINT t_product_materialoutlet_id PRIMARY KEY (id);


--
-- Name: t_product_outlet_stock t_product_outlet_stock_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_product_outlet_stock
    ADD CONSTRAINT t_product_outlet_stock_id PRIMARY KEY (id);


--
-- Name: t_promo t_promo_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_promo
    ADD CONSTRAINT t_promo_id PRIMARY KEY (id);


--
-- Name: t_purchase_order t_purchase_order_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_purchase_order
    ADD CONSTRAINT t_purchase_order_id PRIMARY KEY (id);


--
-- Name: t_registration t_registration_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_registration
    ADD CONSTRAINT t_registration_id PRIMARY KEY (id);


--
-- Name: t_road_plan_approval t_road_plan_approval_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan_approval
    ADD CONSTRAINT t_road_plan_approval_id PRIMARY KEY (id);


--
-- Name: t_road_plan t_road_plan_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan
    ADD CONSTRAINT t_road_plan_id PRIMARY KEY (id);


--
-- Name: t_road_plan_sales t_road_plan_sales_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan_sales
    ADD CONSTRAINT t_road_plan_sales_id PRIMARY KEY (id);


--
-- Name: t_sales_order_delivery t_sales_order_delivery_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery
    ADD CONSTRAINT t_sales_order_delivery_id PRIMARY KEY (id);


--
-- Name: t_sales_order_delivery_item t_sales_order_delivery_item_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item
    ADD CONSTRAINT t_sales_order_delivery_item_id PRIMARY KEY (id);


--
-- Name: t_sales_order_delivery_item_status t_sales_order_delivery_item_status_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item_status
    ADD CONSTRAINT t_sales_order_delivery_item_status_id PRIMARY KEY (id);


--
-- Name: t_sales_order t_sales_order_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order
    ADD CONSTRAINT t_sales_order_id PRIMARY KEY (id);


--
-- Name: t_sales_order_line t_sales_order_line_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_line
    ADD CONSTRAINT t_sales_order_line_id PRIMARY KEY (id);


--
-- Name: t_sales_order_status_history t_sales_order_status_history_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_status_history
    ADD CONSTRAINT t_sales_order_status_history_id PRIMARY KEY (id);


--
-- Name: t_sales_outlet t_sales_outlet_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_outlet
    ADD CONSTRAINT t_sales_outlet_id PRIMARY KEY (id);


--
-- Name: t_sales_target_area t_sales_target_area_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_area
    ADD CONSTRAINT t_sales_target_area_id PRIMARY KEY (id);


--
-- Name: t_sales_target_company t_sales_target_company_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_company
    ADD CONSTRAINT t_sales_target_company_id PRIMARY KEY (id);


--
-- Name: t_sales_target t_sales_target_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target
    ADD CONSTRAINT t_sales_target_id PRIMARY KEY (id);


--
-- Name: t_sales_target_month t_sales_target_month_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_month
    ADD CONSTRAINT t_sales_target_month_id PRIMARY KEY (id);


--
-- Name: t_sales_target_product t_sales_target_product_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_product
    ADD CONSTRAINT t_sales_target_product_id PRIMARY KEY (id);


--
-- Name: t_sales_target_salesman t_sales_target_salesman_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_salesman
    ADD CONSTRAINT t_sales_target_salesman_id PRIMARY KEY (id);


--
-- Name: t_sales_target_segment t_sales_target_segment_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_segment
    ADD CONSTRAINT t_sales_target_segment_id PRIMARY KEY (id);


--
-- Name: t_sales_target_store t_sales_target_store_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_store
    ADD CONSTRAINT t_sales_target_store_id PRIMARY KEY (id);


--
-- Name: t_sales_target_subarea t_sales_target_subarea_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_subarea
    ADD CONSTRAINT t_sales_target_subarea_id PRIMARY KEY (id);


--
-- Name: t_spg_result t_spg_result_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_spg_result
    ADD CONSTRAINT t_spg_result_id PRIMARY KEY (id);


--
-- Name: t_visit_data t_visit_data_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit_data
    ADD CONSTRAINT t_visit_data_id PRIMARY KEY (id);


--
-- Name: t_visit t_visit_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit
    ADD CONSTRAINT t_visit_id PRIMARY KEY (id);


--
-- Name: t_visit_product t_visit_product_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit_product
    ADD CONSTRAINT t_visit_product_id PRIMARY KEY (id);


--
-- Name: t_withdraw t_withdraw_funds_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_withdraw
    ADD CONSTRAINT t_withdraw_funds_id PRIMARY KEY (id);


--
-- Name: t_withdraw_line t_withdraw_line_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_withdraw_line
    ADD CONSTRAINT t_withdraw_line_id PRIMARY KEY (id);


--
-- Name: pr_employee temp_employee_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_employee
    ADD CONSTRAINT temp_employee_id PRIMARY KEY (id);


--
-- Name: pr_task temp_task_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_task
    ADD CONSTRAINT temp_task_id PRIMARY KEY (id);


--
-- Name: x_setting_application x_setting_application_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.x_setting_application
    ADD CONSTRAINT x_setting_application_id PRIMARY KEY (id);


--
-- Name: x_token_application x_token_application_id; Type: CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.x_token_application
    ADD CONSTRAINT x_token_application_id PRIMARY KEY (id);


--
-- Name: hdb_schema_update_event_one_row; Type: INDEX; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE UNIQUE INDEX hdb_schema_update_event_one_row ON hdb_catalog.hdb_schema_update_event USING btree (((occurred_at IS NOT NULL)));


--
-- Name: m_totem_totem_code; Type: INDEX; Schema: public; Owner: prod_kelava
--

CREATE UNIQUE INDEX m_totem_totem_code ON public.m_totem USING btree (totem_code);


--
-- Name: hdb_schema_update_event hdb_schema_update_event_notifier; Type: TRIGGER; Schema: hdb_catalog; Owner: prod_kelava
--

CREATE TRIGGER hdb_schema_update_event_notifier AFTER INSERT OR UPDATE ON hdb_catalog.hdb_schema_update_event FOR EACH ROW EXECUTE PROCEDURE hdb_catalog.hdb_schema_update_event_notifier();


--
-- Name: m_client m_client_bi; Type: TRIGGER; Schema: public; Owner: prod_kelava
--

CREATE TRIGGER m_client_bi BEFORE INSERT ON public.m_client FOR EACH ROW EXECUTE PROCEDURE public.m_client_bi();


--
-- Name: m_contract_approval m_contract_approval_ai; Type: TRIGGER; Schema: public; Owner: prod_kelava
--

CREATE TRIGGER m_contract_approval_ai AFTER INSERT ON public.m_contract_approval FOR EACH ROW EXECUTE PROCEDURE public.m_contract_approval_ai();


--
-- Name: m_contract m_contract_au; Type: TRIGGER; Schema: public; Owner: prod_kelava
--

CREATE TRIGGER m_contract_au AFTER UPDATE ON public.m_contract FOR EACH ROW EXECUTE PROCEDURE public.m_contract_au();


--
-- Name: m_contract m_contract_bi; Type: TRIGGER; Schema: public; Owner: prod_kelava
--

CREATE TRIGGER m_contract_bi BEFORE INSERT ON public.m_contract FOR EACH ROW EXECUTE PROCEDURE public.m_contract_bi();


--
-- Name: m_customer_outlet m_customer_outlet_bi; Type: TRIGGER; Schema: public; Owner: prod_kelava
--

CREATE TRIGGER m_customer_outlet_bi BEFORE INSERT ON public.m_customer_outlet FOR EACH ROW EXECUTE PROCEDURE public.m_customer_outlet_bi();


--
-- Name: t_sales_order t_sales_order_bi; Type: TRIGGER; Schema: public; Owner: prod_kelava
--

CREATE TRIGGER t_sales_order_bi BEFORE INSERT ON public.t_sales_order FOR EACH ROW EXECUTE PROCEDURE public.t_sales_order_bi();


--
-- Name: t_withdraw t_withdraw_bi; Type: TRIGGER; Schema: public; Owner: prod_kelava
--

CREATE TRIGGER t_withdraw_bi BEFORE INSERT ON public.t_withdraw FOR EACH ROW EXECUTE PROCEDURE public.t_withdraw_bi();


--
-- Name: event_triggers event_triggers_schema_name_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.event_triggers
    ADD CONSTRAINT event_triggers_schema_name_fkey FOREIGN KEY (schema_name, table_name) REFERENCES hdb_catalog.hdb_table(table_schema, table_name) ON UPDATE CASCADE;


--
-- Name: hdb_action_permission hdb_action_permission_action_name_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_action_permission
    ADD CONSTRAINT hdb_action_permission_action_name_fkey FOREIGN KEY (action_name) REFERENCES hdb_catalog.hdb_action(action_name) ON UPDATE CASCADE;


--
-- Name: hdb_allowlist hdb_allowlist_collection_name_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_allowlist
    ADD CONSTRAINT hdb_allowlist_collection_name_fkey FOREIGN KEY (collection_name) REFERENCES hdb_catalog.hdb_query_collection(collection_name);


--
-- Name: hdb_computed_field hdb_computed_field_table_schema_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_computed_field
    ADD CONSTRAINT hdb_computed_field_table_schema_fkey FOREIGN KEY (table_schema, table_name) REFERENCES hdb_catalog.hdb_table(table_schema, table_name) ON UPDATE CASCADE;


--
-- Name: hdb_permission hdb_permission_table_schema_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_permission
    ADD CONSTRAINT hdb_permission_table_schema_fkey FOREIGN KEY (table_schema, table_name) REFERENCES hdb_catalog.hdb_table(table_schema, table_name) ON UPDATE CASCADE;


--
-- Name: hdb_relationship hdb_relationship_table_schema_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_relationship
    ADD CONSTRAINT hdb_relationship_table_schema_fkey FOREIGN KEY (table_schema, table_name) REFERENCES hdb_catalog.hdb_table(table_schema, table_name) ON UPDATE CASCADE;


--
-- Name: hdb_remote_relationship hdb_remote_relationship_table_schema_fkey; Type: FK CONSTRAINT; Schema: hdb_catalog; Owner: prod_kelava
--

ALTER TABLE ONLY hdb_catalog.hdb_remote_relationship
    ADD CONSTRAINT hdb_remote_relationship_table_schema_fkey FOREIGN KEY (table_schema, table_name) REFERENCES hdb_catalog.hdb_table(table_schema, table_name) ON UPDATE CASCADE;


--
-- Name: ft_sales_by_product ft_sales_by_product_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.ft_sales_by_product
    ADD CONSTRAINT ft_sales_by_product_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: i_withdraw_line i_withdraw_line_id_withdraw_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.i_withdraw_line
    ADD CONSTRAINT i_withdraw_line_id_withdraw_fkey FOREIGN KEY (id_withdraw) REFERENCES public.i_withdraw(id);


--
-- Name: m_add_on_client m_add_on_client_id_add_on_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_add_on_client
    ADD CONSTRAINT m_add_on_client_id_add_on_fkey FOREIGN KEY (id_add_on) REFERENCES public.m_add_on(id);


--
-- Name: m_add_on_client m_add_on_client_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_add_on_client
    ADD CONSTRAINT m_add_on_client_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_area m_area_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_area
    ADD CONSTRAINT m_area_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_channel_pembayaran m_channel_pembayaran_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_channel_pembayaran
    ADD CONSTRAINT m_channel_pembayaran_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_city m_city_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_city
    ADD CONSTRAINT m_city_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_city m_city_id_province_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_city
    ADD CONSTRAINT m_city_id_province_fkey FOREIGN KEY (id_province) REFERENCES public.m_province(id);


--
-- Name: m_client m_client_active_package_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_client
    ADD CONSTRAINT m_client_active_package_fkey FOREIGN KEY (active_package) REFERENCES public.m_package(id);


--
-- Name: m_client_payment m_client_payment_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_client_payment
    ADD CONSTRAINT m_client_payment_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_contact m_contact_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contact
    ADD CONSTRAINT m_contact_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id);


--
-- Name: m_contact m_contact_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contact
    ADD CONSTRAINT m_contact_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_contact m_contact_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contact
    ADD CONSTRAINT m_contact_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id);


--
-- Name: m_contract_approval m_contract_approval_id_approver_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contract_approval
    ADD CONSTRAINT m_contract_approval_id_approver_fkey FOREIGN KEY (id_approver) REFERENCES public.p_user(id);


--
-- Name: m_contract_approval m_contract_approval_id_contract_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contract_approval
    ADD CONSTRAINT m_contract_approval_id_contract_fkey FOREIGN KEY (id_contract) REFERENCES public.m_contract(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_contract m_contract_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contract
    ADD CONSTRAINT m_contract_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_contract m_contract_id_customer_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contract
    ADD CONSTRAINT m_contract_id_customer_outlet_fkey FOREIGN KEY (id_customer_outlet) REFERENCES public.m_customer_outlet(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_contract_price m_contract_price_id_contract_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contract_price
    ADD CONSTRAINT m_contract_price_id_contract_fkey FOREIGN KEY (id_contract) REFERENCES public.m_contract(id);


--
-- Name: m_contract_price m_contract_price_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_contract_price
    ADD CONSTRAINT m_contract_price_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: m_country m_country_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_country
    ADD CONSTRAINT m_country_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_customer_contact m_customer_contact_id_contact_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_contact
    ADD CONSTRAINT m_customer_contact_id_contact_fkey FOREIGN KEY (id_contact) REFERENCES public.m_contact(id);


--
-- Name: m_customer_contact m_customer_contact_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_contact
    ADD CONSTRAINT m_customer_contact_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id) ON DELETE CASCADE;


--
-- Name: m_customer m_customer_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer
    ADD CONSTRAINT m_customer_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_customer m_customer_id_customer_group_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer
    ADD CONSTRAINT m_customer_id_customer_group_fkey FOREIGN KEY (id_customer_group) REFERENCES public.m_customer_group(id);


--
-- Name: m_customer m_customer_id_segment_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer
    ADD CONSTRAINT m_customer_id_segment_fkey FOREIGN KEY (id_segment) REFERENCES public.m_customer_segment(id);


--
-- Name: m_customer_outlet m_customer_outlet_id_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_id_area_fkey FOREIGN KEY (id_area) REFERENCES public.m_area(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_customer_outlet m_customer_outlet_id_city_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_id_city_fkey FOREIGN KEY (id_city) REFERENCES public.m_city(id);


--
-- Name: m_customer_outlet m_customer_outlet_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_customer_outlet m_customer_outlet_id_contract_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_id_contract_fkey FOREIGN KEY (id_contract) REFERENCES public.m_contract(id);


--
-- Name: m_customer_outlet m_customer_outlet_id_country_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_id_country_fkey FOREIGN KEY (id_country) REFERENCES public.m_country(id);


--
-- Name: m_customer_outlet m_customer_outlet_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id);


--
-- Name: m_customer_outlet m_customer_outlet_id_province_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_id_province_fkey FOREIGN KEY (id_province) REFERENCES public.m_province(id);


--
-- Name: m_customer_outlet m_customer_outlet_id_subarea_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_outlet
    ADD CONSTRAINT m_customer_outlet_id_subarea_fkey FOREIGN KEY (id_subarea) REFERENCES public.m_subarea(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_customer_segment m_customer_segment_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_segment
    ADD CONSTRAINT m_customer_segment_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_customer_social_media m_customer_social_media_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_social_media
    ADD CONSTRAINT m_customer_social_media_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id);


--
-- Name: m_customer_social_media m_customer_social_media_id_sosmed_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_customer_social_media
    ADD CONSTRAINT m_customer_social_media_id_sosmed_fkey FOREIGN KEY (id_sosmed) REFERENCES public.m_sosmed(id);


--
-- Name: m_knowledge m_knowledge_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_knowledge
    ADD CONSTRAINT m_knowledge_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id);


--
-- Name: m_knowledge m_knowledge_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_knowledge
    ADD CONSTRAINT m_knowledge_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_membership_customer m_membership_customer_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_customer
    ADD CONSTRAINT m_membership_customer_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_membership_customer m_membership_customer_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_customer
    ADD CONSTRAINT m_membership_customer_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id);


--
-- Name: m_membership_customer m_membership_customer_id_membership_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_customer
    ADD CONSTRAINT m_membership_customer_id_membership_fkey FOREIGN KEY (id_membership) REFERENCES public.m_membership_level(id);


--
-- Name: m_membership_level m_membership_level_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_level
    ADD CONSTRAINT m_membership_level_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_membership_level m_membership_level_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_level
    ADD CONSTRAINT m_membership_level_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.p_user(id);


--
-- Name: m_opportunity_stage m_opportunity_stage_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_opportunity_stage
    ADD CONSTRAINT m_opportunity_stage_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_outlet_complement m_outlet_complement_m_complement_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement
    ADD CONSTRAINT m_outlet_complement_m_complement_fkey FOREIGN KEY (m_complement) REFERENCES public.m_product_complement(id);


--
-- Name: m_outlet_complement m_outlet_complement_m_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement
    ADD CONSTRAINT m_outlet_complement_m_outlet_fkey FOREIGN KEY (m_outlet) REFERENCES public.m_outlet(id);


--
-- Name: m_outlet_complement_new m_outlet_complement_new_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement_new
    ADD CONSTRAINT m_outlet_complement_new_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: m_outlet_complement_new m_outlet_complement_new_id_product_complement_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement_new
    ADD CONSTRAINT m_outlet_complement_new_id_product_complement_fkey FOREIGN KEY (id_product_complement) REFERENCES public.m_product_complement_new(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_outlet_complement_price m_outlet_complement_price_id_outlet_complement_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_complement_price
    ADD CONSTRAINT m_outlet_complement_price_id_outlet_complement_fkey FOREIGN KEY (id_outlet_complement) REFERENCES public.m_outlet_complement(id);


--
-- Name: m_outlet_complement_price_new m_outlet_complement_price_new_id_outlet_complement_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_complement_price_new
    ADD CONSTRAINT m_outlet_complement_price_new_id_outlet_complement_fkey FOREIGN KEY (id_outlet_complement) REFERENCES public.m_outlet_complement_new(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_outlet_has_channel_pembayaran m_outlet_has_channel_pembayaran_channel_pembayaran_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_has_channel_pembayaran
    ADD CONSTRAINT m_outlet_has_channel_pembayaran_channel_pembayaran_fkey FOREIGN KEY (channel_pembayaran) REFERENCES public.m_channel_pembayaran(id);


--
-- Name: m_outlet_has_channel_pembayaran m_outlet_has_channel_pembayaran_m_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_has_channel_pembayaran
    ADD CONSTRAINT m_outlet_has_channel_pembayaran_m_outlet_fkey FOREIGN KEY (m_outlet) REFERENCES public.m_outlet(id);


--
-- Name: m_outlet m_outlet_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet
    ADD CONSTRAINT m_outlet_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_outlet m_outlet_m_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet
    ADD CONSTRAINT m_outlet_m_area_fkey FOREIGN KEY (m_area) REFERENCES public.m_area(id);


--
-- Name: m_outlet_pic m_outlet_pic_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_pic
    ADD CONSTRAINT m_outlet_pic_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: m_outlet_queue_ads m_outlet_queue_ads_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_queue_ads
    ADD CONSTRAINT m_outlet_queue_ads_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_outlet_queue_ads m_outlet_queue_ads_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_outlet_queue_ads
    ADD CONSTRAINT m_outlet_queue_ads_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: m_outlet_setting m_outlet_setting_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_setting
    ADD CONSTRAINT m_outlet_setting_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_outlet_setting_value m_outlet_setting_value_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_setting_value
    ADD CONSTRAINT m_outlet_setting_value_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: m_outlet_setting_value m_outlet_setting_value_id_outlet_setting_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_outlet_setting_value
    ADD CONSTRAINT m_outlet_setting_value_id_outlet_setting_fkey FOREIGN KEY (id_outlet_setting) REFERENCES public.m_outlet_setting(id);


--
-- Name: m_package_conf m_package_conf_m_package_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_package_conf
    ADD CONSTRAINT m_package_conf_m_package_fkey FOREIGN KEY (m_package) REFERENCES public.m_package(id);


--
-- Name: m_product_bom m_product_bom_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_bom
    ADD CONSTRAINT m_product_bom_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_product_bom m_product_bom_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_bom
    ADD CONSTRAINT m_product_bom_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: m_product_bomdetail m_product_bomdetail_id_product_bom_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_bomdetail
    ADD CONSTRAINT m_product_bomdetail_id_product_bom_fkey FOREIGN KEY (id_product_bom) REFERENCES public.m_product_bom(id);


--
-- Name: m_product_bomdetail m_product_bomdetail_id_product_material_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_bomdetail
    ADD CONSTRAINT m_product_bomdetail_id_product_material_fkey FOREIGN KEY (id_product_material) REFERENCES public.m_product(id);


--
-- Name: m_product_brand m_product_brand_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_brand
    ADD CONSTRAINT m_product_brand_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_product_category m_product_category_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_category
    ADD CONSTRAINT m_product_category_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_product_complement m_product_complement_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_complement
    ADD CONSTRAINT m_product_complement_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_product_complement_new m_product_complement_id_client_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_complement_new
    ADD CONSTRAINT m_product_complement_id_client_fkey1 FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_product_complement_new m_product_complement_id_product_complement_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_complement_new
    ADD CONSTRAINT m_product_complement_id_product_complement_fkey FOREIGN KEY (id_product_complement) REFERENCES public.m_product(id);


--
-- Name: m_product_complement m_product_complement_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_complement
    ADD CONSTRAINT m_product_complement_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: m_product_complement_new m_product_complement_id_product_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_complement_new
    ADD CONSTRAINT m_product_complement_id_product_fkey1 FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: m_product_group m_product_group_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_group
    ADD CONSTRAINT m_product_group_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_product m_product_id_brand_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product
    ADD CONSTRAINT m_product_id_brand_fkey FOREIGN KEY (id_brand) REFERENCES public.m_product_brand(id);


--
-- Name: m_product m_product_id_category_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product
    ADD CONSTRAINT m_product_id_category_fkey FOREIGN KEY (id_category) REFERENCES public.m_product_category(id);


--
-- Name: m_product m_product_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product
    ADD CONSTRAINT m_product_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_product m_product_id_product_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product
    ADD CONSTRAINT m_product_id_product_type_fkey FOREIGN KEY (id_product_type) REFERENCES public.m_product_type(id);


--
-- Name: m_product_material m_product_material_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_material
    ADD CONSTRAINT m_product_material_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_product_outlet_customer_group m_product_outlet_customer_group_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_outlet_customer_group
    ADD CONSTRAINT m_product_outlet_customer_group_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id);


--
-- Name: m_product_outlet_customer_group m_product_outlet_customer_group_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_outlet_customer_group
    ADD CONSTRAINT m_product_outlet_customer_group_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_product_outlet_customer_group m_product_outlet_customer_group_id_customer_group_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_outlet_customer_group
    ADD CONSTRAINT m_product_outlet_customer_group_id_customer_group_fkey FOREIGN KEY (id_customer_group) REFERENCES public.m_customer_group(id);


--
-- Name: m_product_outlet_customer_group m_product_outlet_customer_group_id_product_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_product_outlet_customer_group
    ADD CONSTRAINT m_product_outlet_customer_group_id_product_outlet_fkey FOREIGN KEY (id_product_outlet) REFERENCES public.m_product_outlet(id);


--
-- Name: m_product_outlet m_product_outlet_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet
    ADD CONSTRAINT m_product_outlet_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_product_outlet m_product_outlet_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet
    ADD CONSTRAINT m_product_outlet_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: m_product_outlet m_product_outlet_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet
    ADD CONSTRAINT m_product_outlet_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: m_product_outlet_price m_product_outlet_price_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet_price
    ADD CONSTRAINT m_product_outlet_price_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id);


--
-- Name: m_product_outlet_price m_product_outlet_price_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet_price
    ADD CONSTRAINT m_product_outlet_price_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_product_outlet_price m_product_outlet_price_id_product_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_outlet_price
    ADD CONSTRAINT m_product_outlet_price_id_product_outlet_fkey FOREIGN KEY (id_product_outlet) REFERENCES public.m_product_outlet(id);


--
-- Name: m_product_price m_product_price_id_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_price
    ADD CONSTRAINT m_product_price_id_area_fkey FOREIGN KEY (id_area) REFERENCES public.m_area(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_product_price m_product_price_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_price
    ADD CONSTRAINT m_product_price_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_product_price m_product_price_id_contract_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_price
    ADD CONSTRAINT m_product_price_id_contract_fkey FOREIGN KEY (id_contract) REFERENCES public.m_contract(id);


--
-- Name: m_product_price m_product_price_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_price
    ADD CONSTRAINT m_product_price_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: m_product_subcategory m_product_subcategory_id_product_category_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_subcategory
    ADD CONSTRAINT m_product_subcategory_id_product_category_fkey FOREIGN KEY (id_product_category) REFERENCES public.m_product_category(id);


--
-- Name: m_product_subgroup m_product_subgroup_id_group_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_product_subgroup
    ADD CONSTRAINT m_product_subgroup_id_group_fkey FOREIGN KEY (id_group) REFERENCES public.m_product_group(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_province m_province_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_province
    ADD CONSTRAINT m_province_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_province m_province_id_country_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_province
    ADD CONSTRAINT m_province_id_country_fkey FOREIGN KEY (id_country) REFERENCES public.m_country(id);


--
-- Name: m_setting_value m_setting_value_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_setting_value
    ADD CONSTRAINT m_setting_value_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_setting_value m_setting_value_id_setting_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_setting_value
    ADD CONSTRAINT m_setting_value_id_setting_fkey FOREIGN KEY (id_setting) REFERENCES public.m_setting(id);


--
-- Name: m_sosmed m_sosmed_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_sosmed
    ADD CONSTRAINT m_sosmed_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_subarea m_subarea_id_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_subarea
    ADD CONSTRAINT m_subarea_id_area_fkey FOREIGN KEY (id_area) REFERENCES public.m_area(id);


--
-- Name: m_subregion m_subregion_id_region_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_subregion
    ADD CONSTRAINT m_subregion_id_region_fkey FOREIGN KEY (id_region) REFERENCES public.m_region(id);


--
-- Name: m_totem m_totem_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_totem
    ADD CONSTRAINT m_totem_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_totem m_totem_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_totem
    ADD CONSTRAINT m_totem_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: m_totem m_totem_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_totem
    ADD CONSTRAINT m_totem_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: m_visit_field1 m_visit_field1_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_visit_field1
    ADD CONSTRAINT m_visit_field1_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_visit_field2 m_visit_field2_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_visit_field2
    ADD CONSTRAINT m_visit_field2_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: m_visit_field3 m_visit_field3_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_visit_field3
    ADD CONSTRAINT m_visit_field3_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: pr_project p_project_pic_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_project
    ADD CONSTRAINT p_project_pic_fkey FOREIGN KEY (pic) REFERENCES public.p_user(id);


--
-- Name: p_request_reset_password p_request_reset_password_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.p_request_reset_password
    ADD CONSTRAINT p_request_reset_password_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: p_user_role p_user_role_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.p_user_role
    ADD CONSTRAINT p_user_role_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.p_role(id);


--
-- Name: p_user_role p_user_role_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.p_user_role
    ADD CONSTRAINT p_user_role_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.p_user(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: pr_task pr_task_id_employee_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_task
    ADD CONSTRAINT pr_task_id_employee_fkey FOREIGN KEY (id_employee) REFERENCES public.p_user(id);


--
-- Name: pr_task pr_task_id_project_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_task
    ADD CONSTRAINT pr_task_id_project_fkey FOREIGN KEY (id_project) REFERENCES public.pr_project(id);


--
-- Name: pr_task pr_task_id_task_parent_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_task
    ADD CONSTRAINT pr_task_id_task_parent_fkey FOREIGN KEY (id_task_parent) REFERENCES public.pr_task(id);


--
-- Name: pr_task_realization pr_task_realization_id_task_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.pr_task_realization
    ADD CONSTRAINT pr_task_realization_id_task_fkey FOREIGN KEY (id_task) REFERENCES public.pr_task(id);


--
-- Name: m_customer_group t_customer_group_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.m_customer_group
    ADD CONSTRAINT t_customer_group_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: t_customer_poin t_customer_poin_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_customer_poin
    ADD CONSTRAINT t_customer_poin_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id);


--
-- Name: t_customer_poin t_customer_poin_id_invoice_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_customer_poin
    ADD CONSTRAINT t_customer_poin_id_invoice_fkey FOREIGN KEY (id_sales_order) REFERENCES public.t_sales_order(id);


--
-- Name: t_customer_poin t_customer_poin_id_membership_level_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_customer_poin
    ADD CONSTRAINT t_customer_poin_id_membership_level_fkey FOREIGN KEY (id_membership_level) REFERENCES public.m_membership_level(id);


--
-- Name: t_event_assign t_event_assign_id_event_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_assign
    ADD CONSTRAINT t_event_assign_id_event_fkey FOREIGN KEY (id_event) REFERENCES public.t_event(id);


--
-- Name: t_event_assign t_event_assign_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_assign
    ADD CONSTRAINT t_event_assign_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_event_pic t_event_pic_id_event_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_pic
    ADD CONSTRAINT t_event_pic_id_event_fkey FOREIGN KEY (id_event) REFERENCES public.t_event(id);


--
-- Name: t_event_pic t_event_pic_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_pic
    ADD CONSTRAINT t_event_pic_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_event_result t_event_result_id_event_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_result
    ADD CONSTRAINT t_event_result_id_event_fkey FOREIGN KEY (id_event) REFERENCES public.t_event(id);


--
-- Name: t_event_result t_event_result_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_event_result
    ADD CONSTRAINT t_event_result_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: t_hardware_usage t_hardware_usage_id_contract_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_hardware_usage
    ADD CONSTRAINT t_hardware_usage_id_contract_fkey FOREIGN KEY (id_contract) REFERENCES public.m_contract(id);


--
-- Name: t_hardware_usage t_hardware_usage_id_event_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_hardware_usage
    ADD CONSTRAINT t_hardware_usage_id_event_fkey FOREIGN KEY (id_event) REFERENCES public.t_event(id);


--
-- Name: t_hardware_usage t_hardware_usage_id_hardware_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_hardware_usage
    ADD CONSTRAINT t_hardware_usage_id_hardware_fkey FOREIGN KEY (id_hardware) REFERENCES public.m_hardware(id);


--
-- Name: t_hit t_hit_id_cilent_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_hit
    ADD CONSTRAINT t_hit_id_cilent_fkey FOREIGN KEY (id_cilent) REFERENCES public.m_client(id);


--
-- Name: t_hit t_hit_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_hit
    ADD CONSTRAINT t_hit_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id);


--
-- Name: t_hit t_hit_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_hit
    ADD CONSTRAINT t_hit_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_invoice t_invoice_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_invoice
    ADD CONSTRAINT t_invoice_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id);


--
-- Name: t_invoice t_invoice_id_delivery_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_invoice
    ADD CONSTRAINT t_invoice_id_delivery_fkey FOREIGN KEY (id_delivery) REFERENCES public.t_sales_order_delivery(id);


--
-- Name: m_membership_client t_membership_client_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_client
    ADD CONSTRAINT t_membership_client_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: m_membership_client t_membership_client_id_membership_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.m_membership_client
    ADD CONSTRAINT t_membership_client_id_membership_type_fkey FOREIGN KEY (id_membership_type) REFERENCES public.m_membership_type(id);


--
-- Name: t_news t_news_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_news
    ADD CONSTRAINT t_news_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: t_opportunity t_opportunity_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity
    ADD CONSTRAINT t_opportunity_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id);


--
-- Name: t_opportunity_file t_opportunity_file_id_opportunity_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity_file
    ADD CONSTRAINT t_opportunity_file_id_opportunity_fkey FOREIGN KEY (id_opportunity) REFERENCES public.t_opportunity(id);


--
-- Name: t_opportunity t_opportunity_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity
    ADD CONSTRAINT t_opportunity_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_opportunity t_opportunity_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity
    ADD CONSTRAINT t_opportunity_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id) ON DELETE CASCADE;


--
-- Name: t_opportunity t_opportunity_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity
    ADD CONSTRAINT t_opportunity_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: t_opportunity t_opportunity_id_stage_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity
    ADD CONSTRAINT t_opportunity_id_stage_fkey FOREIGN KEY (id_stage) REFERENCES public.m_opportunity_stage(id);


--
-- Name: t_opportunity_timeline t_opportunity_timeline_id_opportunity_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity_timeline
    ADD CONSTRAINT t_opportunity_timeline_id_opportunity_fkey FOREIGN KEY (id_opportunity) REFERENCES public.t_opportunity(id) ON DELETE CASCADE;


--
-- Name: t_opportunity_timeline t_opportunity_timeline_id_stage_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity_timeline
    ADD CONSTRAINT t_opportunity_timeline_id_stage_fkey FOREIGN KEY (id_stage) REFERENCES public.m_opportunity_stage(id);


--
-- Name: t_opportunity_timeline t_opportunity_timeline_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_opportunity_timeline
    ADD CONSTRAINT t_opportunity_timeline_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.p_user(id);


--
-- Name: t_outlet_charges t_outlet_charges_id_charges_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_outlet_charges
    ADD CONSTRAINT t_outlet_charges_id_charges_fkey FOREIGN KEY (id_charges) REFERENCES public.m_charges(id);


--
-- Name: t_outlet_charges t_outlet_charges_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_outlet_charges
    ADD CONSTRAINT t_outlet_charges_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: t_outlet_charges_value t_outlet_charges_value_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_outlet_charges_value
    ADD CONSTRAINT t_outlet_charges_value_created_by_fkey FOREIGN KEY (updated_by) REFERENCES public.p_user(id);


--
-- Name: t_outlet_charges_value t_outlet_charges_value_id_outlet_charges_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_outlet_charges_value
    ADD CONSTRAINT t_outlet_charges_value_id_outlet_charges_fkey FOREIGN KEY (id_outlet_charges) REFERENCES public.t_outlet_charges(id);


--
-- Name: t_outlet_promo t_outlet_promo_id_product_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_outlet_promo
    ADD CONSTRAINT t_outlet_promo_id_product_outlet_fkey FOREIGN KEY (id_product_outlet) REFERENCES public.m_product_outlet(id);


--
-- Name: t_outlet_queue_date_number t_outlet_queue_date_number_id_outlet_queue_date_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_outlet_queue_date_number
    ADD CONSTRAINT t_outlet_queue_date_number_id_outlet_queue_date_fkey FOREIGN KEY (id_outlet_queue_date) REFERENCES public.t_outlet_queue_date(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_payment_callback_response t_payment_callback_response_id_payment_log_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_payment_callback_response
    ADD CONSTRAINT t_payment_callback_response_id_payment_log_fkey FOREIGN KEY (id_payment_log) REFERENCES public.t_log_payment_gateway(id);


--
-- Name: t_payment t_payment_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_payment
    ADD CONSTRAINT t_payment_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: t_payment t_payment_id_delivery_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_payment
    ADD CONSTRAINT t_payment_id_delivery_fkey FOREIGN KEY (id_delivery) REFERENCES public.t_sales_order_delivery(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_product_outlet_movement t_product_materialoutlet_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_product_outlet_movement
    ADD CONSTRAINT t_product_materialoutlet_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: t_product_outlet_movement t_product_materialoutlet_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_product_outlet_movement
    ADD CONSTRAINT t_product_materialoutlet_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: t_product_outlet_movement t_product_materialoutlet_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_product_outlet_movement
    ADD CONSTRAINT t_product_materialoutlet_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: t_product_outlet_movement t_product_materialoutlet_id_sales_order_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_product_outlet_movement
    ADD CONSTRAINT t_product_materialoutlet_id_sales_order_fkey FOREIGN KEY (id_sales_order) REFERENCES public.t_sales_order(id);


--
-- Name: t_product_outlet_stock t_product_outlet_stock_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_product_outlet_stock
    ADD CONSTRAINT t_product_outlet_stock_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: t_product_outlet_stock t_product_outlet_stock_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_product_outlet_stock
    ADD CONSTRAINT t_product_outlet_stock_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: t_product_outlet_stock t_product_outlet_stock_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.t_product_outlet_stock
    ADD CONSTRAINT t_product_outlet_stock_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: t_promo t_promo_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_promo
    ADD CONSTRAINT t_promo_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id);


--
-- Name: t_promo t_promo_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_promo
    ADD CONSTRAINT t_promo_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: t_purchase_order t_purchase_order_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_purchase_order
    ADD CONSTRAINT t_purchase_order_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id);


--
-- Name: t_purchase_order t_purchase_order_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_purchase_order
    ADD CONSTRAINT t_purchase_order_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_purchase_order t_purchase_order_id_vendor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_purchase_order
    ADD CONSTRAINT t_purchase_order_id_vendor_fkey FOREIGN KEY (id_vendor) REFERENCES public.m_customer(id);


--
-- Name: t_road_plan_approval t_road_plan_approval_id_approver_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan_approval
    ADD CONSTRAINT t_road_plan_approval_id_approver_fkey FOREIGN KEY (id_approver) REFERENCES public.p_user(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_road_plan t_road_plan_id_approval_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan
    ADD CONSTRAINT t_road_plan_id_approval_fkey FOREIGN KEY (id_approval) REFERENCES public.t_road_plan_approval(id);


--
-- Name: t_road_plan t_road_plan_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan
    ADD CONSTRAINT t_road_plan_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_road_plan t_road_plan_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan
    ADD CONSTRAINT t_road_plan_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id) ON DELETE CASCADE;


--
-- Name: t_road_plan t_road_plan_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan
    ADD CONSTRAINT t_road_plan_id_outlet_fkey FOREIGN KEY (id_customer_outlet) REFERENCES public.m_customer_outlet(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_road_plan t_road_plan_id_outlet_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan
    ADD CONSTRAINT t_road_plan_id_outlet_fkey1 FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: t_road_plan t_road_plan_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan
    ADD CONSTRAINT t_road_plan_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_road_plan_sales t_road_plan_sales_id_road_plan_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_road_plan_sales
    ADD CONSTRAINT t_road_plan_sales_id_road_plan_fkey FOREIGN KEY (id_road_plan) REFERENCES public.t_road_plan(id);


--
-- Name: t_sales_order t_sales_order_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order
    ADD CONSTRAINT t_sales_order_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: t_sales_order_delivery t_sales_order_delivery_id_sales_order_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery
    ADD CONSTRAINT t_sales_order_delivery_id_sales_order_fkey FOREIGN KEY (id_sales_order) REFERENCES public.t_sales_order(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_order_delivery_item t_sales_order_delivery_item_id_deilvery_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item
    ADD CONSTRAINT t_sales_order_delivery_item_id_deilvery_fkey FOREIGN KEY (id_delivery) REFERENCES public.t_sales_order_delivery(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_order_delivery_item t_sales_order_delivery_item_id_delivery_item_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item
    ADD CONSTRAINT t_sales_order_delivery_item_id_delivery_item_status_fkey FOREIGN KEY (id_delivery_item_status) REFERENCES public.t_sales_order_delivery_item_status(id);


--
-- Name: t_sales_order_delivery_item t_sales_order_delivery_item_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item
    ADD CONSTRAINT t_sales_order_delivery_item_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_order_delivery_item t_sales_order_delivery_item_id_sales_order_line_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item
    ADD CONSTRAINT t_sales_order_delivery_item_id_sales_order_line_fkey FOREIGN KEY (id_sales_order_line) REFERENCES public.t_sales_order_line(id);


--
-- Name: t_sales_order_delivery_item_status t_sales_order_delivery_item_status_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item_status
    ADD CONSTRAINT t_sales_order_delivery_item_status_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id);


--
-- Name: t_sales_order_delivery_item t_sales_order_delivery_item_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_delivery_item
    ADD CONSTRAINT t_sales_order_delivery_item_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.p_user(id);


--
-- Name: t_sales_order t_sales_order_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order
    ADD CONSTRAINT t_sales_order_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id) ON DELETE CASCADE;


--
-- Name: t_sales_order t_sales_order_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order
    ADD CONSTRAINT t_sales_order_id_outlet_fkey FOREIGN KEY (id_customer_outlet) REFERENCES public.m_outlet(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_order t_sales_order_id_outlet_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order
    ADD CONSTRAINT t_sales_order_id_outlet_fkey1 FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: t_sales_order_line t_sales_order_line_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_line
    ADD CONSTRAINT t_sales_order_line_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: t_sales_order_line t_sales_order_line_id_sales_order_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_line
    ADD CONSTRAINT t_sales_order_line_id_sales_order_fkey FOREIGN KEY (id_sales_order) REFERENCES public.t_sales_order(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_order_status_history t_sales_order_status_history_sales_order_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_order_status_history
    ADD CONSTRAINT t_sales_order_status_history_sales_order_fkey FOREIGN KEY (sales_order) REFERENCES public.t_sales_order(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_outlet t_sales_outlet_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_outlet
    ADD CONSTRAINT t_sales_outlet_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_customer_outlet(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_outlet t_sales_outlet_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_outlet
    ADD CONSTRAINT t_sales_outlet_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_sales_target_area t_sales_target_area_id_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_area
    ADD CONSTRAINT t_sales_target_area_id_area_fkey FOREIGN KEY (id_area) REFERENCES public.m_area(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_target_area t_sales_target_area_id_target_month_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_area
    ADD CONSTRAINT t_sales_target_area_id_target_month_fkey FOREIGN KEY (id_target_month) REFERENCES public.t_sales_target_month(id);


--
-- Name: t_sales_target_company t_sales_target_company_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_company
    ADD CONSTRAINT t_sales_target_company_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_target t_sales_target_id_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target
    ADD CONSTRAINT t_sales_target_id_area_fkey FOREIGN KEY (id_area) REFERENCES public.m_area(id);


--
-- Name: t_sales_target t_sales_target_id_customer_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target
    ADD CONSTRAINT t_sales_target_id_customer_outlet_fkey FOREIGN KEY (id_customer_outlet) REFERENCES public.m_customer_outlet(id);


--
-- Name: t_sales_target t_sales_target_id_customer_segment_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target
    ADD CONSTRAINT t_sales_target_id_customer_segment_fkey FOREIGN KEY (id_customer_segment) REFERENCES public.m_customer_segment(id);


--
-- Name: t_sales_target t_sales_target_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target
    ADD CONSTRAINT t_sales_target_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: t_sales_target t_sales_target_id_target_company_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target
    ADD CONSTRAINT t_sales_target_id_target_company_fkey FOREIGN KEY (id_target_company) REFERENCES public.t_sales_target_company(id);


--
-- Name: t_sales_target t_sales_target_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target
    ADD CONSTRAINT t_sales_target_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_sales_target_month t_sales_target_month_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_month
    ADD CONSTRAINT t_sales_target_month_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_target_month t_sales_target_month_id_target_company_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_month
    ADD CONSTRAINT t_sales_target_month_id_target_company_fkey FOREIGN KEY (id_target_company) REFERENCES public.t_sales_target_company(id);


--
-- Name: t_sales_target_product t_sales_target_product_id_client_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_product
    ADD CONSTRAINT t_sales_target_product_id_client_fkey FOREIGN KEY (id_client) REFERENCES public.m_client(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_target_product t_sales_target_product_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_product
    ADD CONSTRAINT t_sales_target_product_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id);


--
-- Name: t_sales_target_product t_sales_target_product_id_product_group_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_product
    ADD CONSTRAINT t_sales_target_product_id_product_group_fkey FOREIGN KEY (id_product_group) REFERENCES public.m_product_group(id);


--
-- Name: t_sales_target_product t_sales_target_product_id_target_month_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_product
    ADD CONSTRAINT t_sales_target_product_id_target_month_fkey FOREIGN KEY (id_target_month) REFERENCES public.t_sales_target_month(id);


--
-- Name: t_sales_target_product t_sales_target_product_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_product
    ADD CONSTRAINT t_sales_target_product_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_sales_target_salesman t_sales_target_salesman_id_target_segment_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_salesman
    ADD CONSTRAINT t_sales_target_salesman_id_target_segment_fkey FOREIGN KEY (id_target_segment) REFERENCES public.t_sales_target_segment(id);


--
-- Name: t_sales_target_salesman t_sales_target_salesman_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_salesman
    ADD CONSTRAINT t_sales_target_salesman_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_sales_target_segment t_sales_target_segment_id_customer_segment_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_segment
    ADD CONSTRAINT t_sales_target_segment_id_customer_segment_fkey FOREIGN KEY (id_customer_segment) REFERENCES public.m_customer_segment(id);


--
-- Name: t_sales_target_segment t_sales_target_segment_id_target_subarea_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_segment
    ADD CONSTRAINT t_sales_target_segment_id_target_subarea_fkey FOREIGN KEY (id_target_subarea) REFERENCES public.t_sales_target_subarea(id);


--
-- Name: t_sales_target_store t_sales_target_store_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_store
    ADD CONSTRAINT t_sales_target_store_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_customer_outlet(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: t_sales_target_store t_sales_target_store_id_segment_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_store
    ADD CONSTRAINT t_sales_target_store_id_segment_fkey FOREIGN KEY (id_segment) REFERENCES public.m_customer_segment(id);


--
-- Name: t_sales_target_store t_sales_target_store_id_target_month_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_store
    ADD CONSTRAINT t_sales_target_store_id_target_month_fkey FOREIGN KEY (id_target_month) REFERENCES public.t_sales_target_month(id);


--
-- Name: t_sales_target_subarea t_sales_target_subarea_id_subarea_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_subarea
    ADD CONSTRAINT t_sales_target_subarea_id_subarea_fkey FOREIGN KEY (id_subarea) REFERENCES public.m_subarea(id);


--
-- Name: t_sales_target_subarea t_sales_target_subarea_id_target_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_sales_target_subarea
    ADD CONSTRAINT t_sales_target_subarea_id_target_area_fkey FOREIGN KEY (id_target_area) REFERENCES public.t_sales_target_area(id);


--
-- Name: t_spg_result t_spg_result_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_spg_result
    ADD CONSTRAINT t_spg_result_id_outlet_fkey FOREIGN KEY (id_outlet) REFERENCES public.m_customer_outlet(id);


--
-- Name: t_spg_result t_spg_result_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_spg_result
    ADD CONSTRAINT t_spg_result_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_visit_data t_visit_data_id_visit_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit_data
    ADD CONSTRAINT t_visit_data_id_visit_fkey FOREIGN KEY (id_visit) REFERENCES public.t_visit(id);


--
-- Name: t_visit t_visit_id_customer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit
    ADD CONSTRAINT t_visit_id_customer_fkey FOREIGN KEY (id_customer) REFERENCES public.m_customer(id) ON DELETE CASCADE;


--
-- Name: t_visit t_visit_id_outlet_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit
    ADD CONSTRAINT t_visit_id_outlet_fkey FOREIGN KEY (id_customer_outlet) REFERENCES public.m_customer_outlet(id);


--
-- Name: t_visit t_visit_id_outlet_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit
    ADD CONSTRAINT t_visit_id_outlet_fkey1 FOREIGN KEY (id_outlet) REFERENCES public.m_outlet(id);


--
-- Name: t_visit t_visit_id_road_plan_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit
    ADD CONSTRAINT t_visit_id_road_plan_fkey FOREIGN KEY (id_road_plan) REFERENCES public.t_road_plan(id) ON DELETE CASCADE;


--
-- Name: t_visit t_visit_id_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit
    ADD CONSTRAINT t_visit_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.p_user(id);


--
-- Name: t_visit_product t_visit_product_id_product_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit_product
    ADD CONSTRAINT t_visit_product_id_product_fkey FOREIGN KEY (id_product) REFERENCES public.m_product(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: t_visit_product t_visit_product_id_visit_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_visit_product
    ADD CONSTRAINT t_visit_product_id_visit_fkey FOREIGN KEY (id_visit) REFERENCES public.t_visit(id);


--
-- Name: t_withdraw_line t_withdraw_line_id_withdraw_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.t_withdraw_line
    ADD CONSTRAINT t_withdraw_line_id_withdraw_fkey FOREIGN KEY (id_withdraw) REFERENCES public.t_withdraw(id);


--
-- Name: x_token_application x_token_application_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prod_kelava
--

ALTER TABLE ONLY public.x_token_application
    ADD CONSTRAINT x_token_application_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.p_user(id);


--
-- Name: sfa_publication; Type: PUBLICATION; Schema: -; Owner: postgres
--

CREATE PUBLICATION sfa_publication FOR ALL TABLES WITH (publish = 'insert, update, delete');


ALTER PUBLICATION sfa_publication OWNER TO postgres;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA public TO prod_kelava;


--
-- Name: TABLE event_triggers; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.event_triggers TO replicator;


--
-- Name: TABLE hdb_action; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_action TO replicator;


--
-- Name: TABLE hdb_action_permission; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_action_permission TO replicator;


--
-- Name: TABLE hdb_allowlist; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_allowlist TO replicator;


--
-- Name: TABLE hdb_check_constraint; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_check_constraint TO replicator;


--
-- Name: TABLE hdb_computed_field; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_computed_field TO replicator;


--
-- Name: TABLE hdb_computed_field_function; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_computed_field_function TO replicator;


--
-- Name: TABLE hdb_cron_triggers; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_cron_triggers TO replicator;


--
-- Name: TABLE hdb_custom_types; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_custom_types TO replicator;


--
-- Name: TABLE hdb_foreign_key_constraint; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_foreign_key_constraint TO replicator;


--
-- Name: TABLE hdb_function; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_function TO replicator;


--
-- Name: TABLE hdb_function_agg; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_function_agg TO replicator;


--
-- Name: TABLE hdb_function_info_agg; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_function_info_agg TO replicator;


--
-- Name: TABLE hdb_permission; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_permission TO replicator;


--
-- Name: TABLE hdb_permission_agg; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_permission_agg TO replicator;


--
-- Name: TABLE hdb_primary_key; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_primary_key TO replicator;


--
-- Name: TABLE hdb_query_collection; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_query_collection TO replicator;


--
-- Name: TABLE hdb_relationship; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_relationship TO replicator;


--
-- Name: TABLE hdb_remote_relationship; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_remote_relationship TO replicator;


--
-- Name: TABLE hdb_role; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_role TO replicator;


--
-- Name: TABLE hdb_schema_update_event; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_schema_update_event TO replicator;


--
-- Name: TABLE hdb_table; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_table TO replicator;


--
-- Name: TABLE hdb_table_info_agg; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_table_info_agg TO replicator;


--
-- Name: TABLE hdb_unique_constraint; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.hdb_unique_constraint TO replicator;


--
-- Name: TABLE remote_schemas; Type: ACL; Schema: hdb_catalog; Owner: prod_kelava
--

GRANT ALL ON TABLE hdb_catalog.remote_schemas TO replicator;


--
-- Name: TABLE bulan_indo; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.bulan_indo TO replicator;


--
-- Name: SEQUENCE event_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.event_id_seq TO replicator;


--
-- Name: TABLE ft_sales_by_product; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.ft_sales_by_product TO replicator;


--
-- Name: TABLE i_withdraw; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.i_withdraw TO replicator;


--
-- Name: SEQUENCE i_withdraw_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.i_withdraw_id_seq TO replicator;


--
-- Name: TABLE i_withdraw_line; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.i_withdraw_line TO replicator;


--
-- Name: SEQUENCE i_withdraw_line_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.i_withdraw_line_id_seq TO replicator;


--
-- Name: TABLE m_add_on; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_add_on TO replicator;


--
-- Name: TABLE m_add_on_client; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_add_on_client TO replicator;


--
-- Name: SEQUENCE m_add_on_client_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_add_on_client_id_seq TO replicator;


--
-- Name: SEQUENCE m_add_on_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_add_on_id_seq TO replicator;


--
-- Name: SEQUENCE m_area_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_area_id_seq TO replicator;


--
-- Name: TABLE m_area; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_area TO replicator;


--
-- Name: TABLE m_channel_pembayaran; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_channel_pembayaran TO replicator;


--
-- Name: SEQUENCE m_channel_pembayaran_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_channel_pembayaran_id_seq TO replicator;


--
-- Name: TABLE m_charges; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.m_charges TO prod_kelava;
GRANT ALL ON TABLE public.m_charges TO replicator;


--
-- Name: SEQUENCE m_charges_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.m_charges_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.m_charges_id_seq TO replicator;


--
-- Name: SEQUENCE m_city_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_city_id_seq TO replicator;


--
-- Name: TABLE m_city; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_city TO replicator;


--
-- Name: TABLE m_client; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_client TO replicator;


--
-- Name: SEQUENCE m_client_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_client_id_seq TO replicator;


--
-- Name: TABLE m_client_packages; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_client_packages TO replicator;


--
-- Name: SEQUENCE m_client_packages_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_client_packages_id_seq TO replicator;


--
-- Name: TABLE m_client_payment; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_client_payment TO replicator;


--
-- Name: SEQUENCE m_client_payment_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_client_payment_id_seq TO replicator;


--
-- Name: TABLE m_contact; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_contact TO replicator;


--
-- Name: SEQUENCE m_contract_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_contract_id_seq TO replicator;


--
-- Name: TABLE m_contract; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_contract TO replicator;


--
-- Name: SEQUENCE m_contract_approval_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_contract_approval_id_seq TO replicator;


--
-- Name: TABLE m_contract_approval; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_contract_approval TO replicator;


--
-- Name: SEQUENCE m_contract_price_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_contract_price_id_seq TO replicator;


--
-- Name: TABLE m_contract_price; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_contract_price TO replicator;


--
-- Name: SEQUENCE m_country_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_country_id_seq TO replicator;


--
-- Name: TABLE m_country; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_country TO replicator;


--
-- Name: SEQUENCE m_customer_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_customer_id_seq TO replicator;


--
-- Name: TABLE m_customer; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_customer TO replicator;


--
-- Name: TABLE m_customer_contact; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_customer_contact TO replicator;


--
-- Name: SEQUENCE m_customer_contact_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_customer_contact_id_seq TO replicator;


--
-- Name: SEQUENCE m_customer_contact_id_seq1; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_customer_contact_id_seq1 TO replicator;


--
-- Name: TABLE m_customer_devices; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.m_customer_devices TO prod_kelava;
GRANT ALL ON TABLE public.m_customer_devices TO replicator;


--
-- Name: SEQUENCE m_customer_devices_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.m_customer_devices_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.m_customer_devices_id_seq TO replicator;


--
-- Name: TABLE m_customer_group; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.m_customer_group TO prod_kelava;
GRANT ALL ON TABLE public.m_customer_group TO replicator;


--
-- Name: SEQUENCE m_customer_outlet_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_customer_outlet_id_seq TO replicator;


--
-- Name: TABLE m_customer_outlet; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_customer_outlet TO replicator;


--
-- Name: SEQUENCE m_customer_segment_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_customer_segment_id_seq TO replicator;


--
-- Name: TABLE m_customer_segment; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_customer_segment TO replicator;


--
-- Name: TABLE m_customer_social_media; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_customer_social_media TO replicator;


--
-- Name: SEQUENCE m_customer_social_media_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_customer_social_media_id_seq TO replicator;


--
-- Name: TABLE m_visit_field1; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_visit_field1 TO replicator;


--
-- Name: SEQUENCE m_field1_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_field1_id_seq TO replicator;


--
-- Name: SEQUENCE m_hardware_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_hardware_id_seq TO replicator;


--
-- Name: TABLE m_hardware; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_hardware TO replicator;


--
-- Name: TABLE m_hour; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_hour TO replicator;


--
-- Name: TABLE m_knowledge; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_knowledge TO replicator;


--
-- Name: SEQUENCE m_knowledge_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_knowledge_id_seq TO replicator;


--
-- Name: TABLE m_membership_client; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_membership_client TO replicator;


--
-- Name: TABLE m_membership_customer; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_membership_customer TO replicator;


--
-- Name: SEQUENCE m_membership_customer_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_membership_customer_id_seq TO replicator;


--
-- Name: TABLE m_membership_level; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_membership_level TO replicator;


--
-- Name: SEQUENCE m_membership_level_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_membership_level_id_seq TO replicator;


--
-- Name: TABLE m_membership_type; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_membership_type TO replicator;


--
-- Name: SEQUENCE m_membership_type_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_membership_type_id_seq TO replicator;


--
-- Name: TABLE m_opportunity_stage; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_opportunity_stage TO replicator;


--
-- Name: SEQUENCE m_opportunity_stage_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_opportunity_stage_id_seq TO replicator;


--
-- Name: TABLE m_outlet; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_outlet TO replicator;


--
-- Name: TABLE m_outlet_complement; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_outlet_complement TO replicator;


--
-- Name: SEQUENCE m_outlet_complement_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_outlet_complement_id_seq TO replicator;


--
-- Name: TABLE m_outlet_complement_new; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_outlet_complement_new TO replicator;


--
-- Name: SEQUENCE m_outlet_complement_new_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_outlet_complement_new_id_seq TO replicator;


--
-- Name: TABLE m_outlet_complement_price; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_outlet_complement_price TO replicator;


--
-- Name: SEQUENCE m_outlet_complement_price_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_outlet_complement_price_id_seq TO replicator;


--
-- Name: TABLE m_outlet_complement_price_new; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.m_outlet_complement_price_new TO prod_kelava;
GRANT ALL ON TABLE public.m_outlet_complement_price_new TO replicator;


--
-- Name: SEQUENCE m_outlet_complement_price_new_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.m_outlet_complement_price_new_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.m_outlet_complement_price_new_id_seq TO replicator;


--
-- Name: TABLE m_outlet_has_channel_pembayaran; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_outlet_has_channel_pembayaran TO replicator;


--
-- Name: SEQUENCE m_outlet_has_channel_pembayaran_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_outlet_has_channel_pembayaran_id_seq TO replicator;


--
-- Name: SEQUENCE m_outlet_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_outlet_id_seq TO replicator;


--
-- Name: TABLE m_outlet_pic; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_outlet_pic TO replicator;


--
-- Name: SEQUENCE m_outlet_pic_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_outlet_pic_id_seq TO replicator;


--
-- Name: TABLE m_outlet_queue_ads; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_outlet_queue_ads TO replicator;


--
-- Name: SEQUENCE m_outlet_queue_ads_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_outlet_queue_ads_id_seq TO replicator;


--
-- Name: TABLE m_outlet_setting; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.m_outlet_setting TO prod_kelava;
GRANT ALL ON TABLE public.m_outlet_setting TO replicator;


--
-- Name: SEQUENCE m_outlet_setting_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.m_outlet_setting_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.m_outlet_setting_id_seq TO replicator;


--
-- Name: TABLE m_outlet_setting_value; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.m_outlet_setting_value TO prod_kelava;
GRANT ALL ON TABLE public.m_outlet_setting_value TO replicator;


--
-- Name: SEQUENCE m_outlet_setting_value_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.m_outlet_setting_value_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.m_outlet_setting_value_id_seq TO replicator;


--
-- Name: TABLE m_package; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_package TO replicator;


--
-- Name: TABLE m_package_conf; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_package_conf TO replicator;


--
-- Name: SEQUENCE m_package_conf_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_package_conf_id_seq TO replicator;


--
-- Name: SEQUENCE m_package_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_package_id_seq TO replicator;


--
-- Name: SEQUENCE m_product_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_id_seq TO replicator;


--
-- Name: TABLE m_product; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product TO replicator;


--
-- Name: TABLE m_product_bom; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_bom TO replicator;


--
-- Name: SEQUENCE m_product_bom_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_bom_id_seq TO replicator;


--
-- Name: TABLE m_product_bomdetail; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_bomdetail TO replicator;


--
-- Name: SEQUENCE m_product_bomdetail_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_bomdetail_id_seq TO replicator;


--
-- Name: SEQUENCE m_product_brand_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_brand_id_seq TO replicator;


--
-- Name: TABLE m_product_brand; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_brand TO replicator;


--
-- Name: SEQUENCE m_product_category_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_category_id_seq TO replicator;


--
-- Name: TABLE m_product_category; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_category TO replicator;


--
-- Name: TABLE m_product_complement; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_complement TO replicator;


--
-- Name: SEQUENCE m_product_complement_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_complement_id_seq TO replicator;


--
-- Name: TABLE m_product_complement_new; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.m_product_complement_new TO prod_kelava;
GRANT ALL ON TABLE public.m_product_complement_new TO replicator;


--
-- Name: SEQUENCE m_product_complement_id_seq1; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.m_product_complement_id_seq1 TO prod_kelava;
GRANT ALL ON SEQUENCE public.m_product_complement_id_seq1 TO replicator;


--
-- Name: SEQUENCE m_product_group_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_group_id_seq TO replicator;


--
-- Name: TABLE m_product_group; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_group TO replicator;


--
-- Name: TABLE m_product_material; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_material TO replicator;


--
-- Name: SEQUENCE m_product_material_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_material_id_seq TO replicator;


--
-- Name: TABLE m_product_outlet; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_outlet TO replicator;


--
-- Name: TABLE m_product_outlet_customer_group; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.m_product_outlet_customer_group TO prod_kelava;
GRANT ALL ON TABLE public.m_product_outlet_customer_group TO replicator;


--
-- Name: SEQUENCE m_product_outlet_customer_group_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.m_product_outlet_customer_group_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.m_product_outlet_customer_group_id_seq TO replicator;


--
-- Name: SEQUENCE m_product_outlet_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_outlet_id_seq TO replicator;


--
-- Name: TABLE m_product_outlet_price; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_outlet_price TO replicator;


--
-- Name: SEQUENCE m_product_outlet_price_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_outlet_price_id_seq TO replicator;


--
-- Name: SEQUENCE m_product_price_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_price_id_seq TO replicator;


--
-- Name: TABLE m_product_price; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_price TO replicator;


--
-- Name: TABLE m_product_subcategory; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_subcategory TO replicator;


--
-- Name: SEQUENCE m_product_subcategory_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_subcategory_id_seq TO replicator;


--
-- Name: SEQUENCE m_product_subgroup_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_subgroup_id_seq TO replicator;


--
-- Name: TABLE m_product_subgroup; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_subgroup TO replicator;


--
-- Name: TABLE m_product_type; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.m_product_type TO prod_kelava;
GRANT ALL ON TABLE public.m_product_type TO replicator;


--
-- Name: SEQUENCE m_product_type_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.m_product_type_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.m_product_type_id_seq TO replicator;


--
-- Name: TABLE m_product_unit; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_product_unit TO replicator;


--
-- Name: SEQUENCE m_product_unit_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_product_unit_id_seq TO replicator;


--
-- Name: SEQUENCE m_province_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_province_id_seq TO replicator;


--
-- Name: TABLE m_province; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_province TO replicator;


--
-- Name: SEQUENCE m_region_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_region_id_seq TO replicator;


--
-- Name: TABLE m_region; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_region TO replicator;


--
-- Name: TABLE m_setting; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_setting TO replicator;


--
-- Name: SEQUENCE m_setting_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_setting_id_seq TO replicator;


--
-- Name: TABLE m_setting_value; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_setting_value TO replicator;


--
-- Name: SEQUENCE m_setting_value_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_setting_value_id_seq TO replicator;


--
-- Name: TABLE m_sosmed; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_sosmed TO replicator;


--
-- Name: SEQUENCE m_sosmed_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_sosmed_id_seq TO replicator;


--
-- Name: SEQUENCE m_subarea_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_subarea_id_seq TO replicator;


--
-- Name: TABLE m_subarea; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_subarea TO replicator;


--
-- Name: SEQUENCE m_subregion_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_subregion_id_seq TO replicator;


--
-- Name: TABLE m_subregion; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_subregion TO replicator;


--
-- Name: TABLE m_totem; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_totem TO replicator;


--
-- Name: SEQUENCE m_totem_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_totem_id_seq TO replicator;


--
-- Name: TABLE m_visit_field2; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_visit_field2 TO replicator;


--
-- Name: SEQUENCE m_visit_field2_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_visit_field2_id_seq TO replicator;


--
-- Name: TABLE m_visit_field3; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.m_visit_field3 TO replicator;


--
-- Name: SEQUENCE m_visit_field3_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.m_visit_field3_id_seq TO replicator;


--
-- Name: TABLE p_migration; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.p_migration TO replicator;


--
-- Name: SEQUENCE p_project_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.p_project_id_seq TO replicator;


--
-- Name: TABLE p_request_reset_password; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.p_request_reset_password TO replicator;


--
-- Name: SEQUENCE p_request_reset_password_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.p_request_reset_password_id_seq TO replicator;


--
-- Name: SEQUENCE p_role_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.p_role_id_seq TO replicator;


--
-- Name: TABLE p_role; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.p_role TO replicator;


--
-- Name: SEQUENCE p_user_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.p_user_id_seq TO replicator;


--
-- Name: TABLE p_user; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.p_user TO replicator;


--
-- Name: SEQUENCE p_user_role_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.p_user_role_id_seq TO replicator;


--
-- Name: TABLE p_user_role; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.p_user_role TO replicator;


--
-- Name: SEQUENCE temp_employee_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.temp_employee_id_seq TO replicator;


--
-- Name: TABLE pr_employee; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.pr_employee TO replicator;


--
-- Name: TABLE pr_project; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.pr_project TO replicator;


--
-- Name: SEQUENCE pr_target_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.pr_target_id_seq TO replicator;


--
-- Name: TABLE pr_target; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.pr_target TO replicator;


--
-- Name: SEQUENCE temp_task_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.temp_task_id_seq TO replicator;


--
-- Name: TABLE pr_task; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.pr_task TO replicator;


--
-- Name: SEQUENCE temp_task_emp_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.temp_task_emp_id_seq TO replicator;


--
-- Name: TABLE pr_task_emp; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.pr_task_emp TO replicator;


--
-- Name: SEQUENCE pr_task_product_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.pr_task_product_id_seq TO replicator;


--
-- Name: SEQUENCE pr_task_realization_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.pr_task_realization_id_seq TO replicator;


--
-- Name: TABLE pr_task_realization; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.pr_task_realization TO replicator;


--
-- Name: TABLE s_pos; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.s_pos TO replicator;


--
-- Name: SEQUENCE s_pos_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.s_pos_id_seq TO replicator;


--
-- Name: SEQUENCE t_customer_group_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.t_customer_group_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.t_customer_group_id_seq TO replicator;


--
-- Name: TABLE t_customer_poin; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_customer_poin TO replicator;


--
-- Name: SEQUENCE t_customer_poin_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_customer_poin_id_seq TO replicator;


--
-- Name: TABLE t_event; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_event TO replicator;


--
-- Name: TABLE t_event_pic; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_event_pic TO replicator;


--
-- Name: SEQUENCE t_event_pic_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_event_pic_id_seq TO replicator;


--
-- Name: TABLE t_event_assign; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_event_assign TO replicator;


--
-- Name: SEQUENCE t_event_assign_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_event_assign_id_seq TO replicator;


--
-- Name: SEQUENCE t_event_result_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_event_result_id_seq TO replicator;


--
-- Name: TABLE t_event_result; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_event_result TO replicator;


--
-- Name: SEQUENCE t_hardware_usage_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_hardware_usage_id_seq TO replicator;


--
-- Name: TABLE t_hardware_usage; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_hardware_usage TO replicator;


--
-- Name: TABLE t_hit; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_hit TO replicator;


--
-- Name: SEQUENCE t_hit_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_hit_id_seq TO replicator;


--
-- Name: TABLE t_invoice; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_invoice TO replicator;


--
-- Name: SEQUENCE t_invoice_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_invoice_id_seq TO replicator;


--
-- Name: TABLE t_log_payment_gateway; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_log_payment_gateway TO replicator;


--
-- Name: SEQUENCE t_log_payment_gateway_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_log_payment_gateway_id_seq TO replicator;


--
-- Name: SEQUENCE t_membership_client_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_membership_client_id_seq TO replicator;


--
-- Name: TABLE t_news; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_news TO replicator;


--
-- Name: SEQUENCE t_news_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_news_id_seq TO replicator;


--
-- Name: TABLE t_opportunity; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_opportunity TO replicator;


--
-- Name: TABLE t_opportunity_file; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_opportunity_file TO replicator;


--
-- Name: SEQUENCE t_opportunity_file_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_opportunity_file_id_seq TO replicator;


--
-- Name: SEQUENCE t_opportunity_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_opportunity_id_seq TO replicator;


--
-- Name: TABLE t_opportunity_timeline; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_opportunity_timeline TO replicator;


--
-- Name: SEQUENCE t_opportunity_timeline_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_opportunity_timeline_id_seq TO replicator;


--
-- Name: TABLE t_otp_log; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_otp_log TO replicator;


--
-- Name: SEQUENCE t_otp_log_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_otp_log_id_seq TO replicator;


--
-- Name: TABLE t_outlet_charges; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.t_outlet_charges TO prod_kelava;
GRANT ALL ON TABLE public.t_outlet_charges TO replicator;


--
-- Name: SEQUENCE t_outlet_charges_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.t_outlet_charges_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.t_outlet_charges_id_seq TO replicator;


--
-- Name: TABLE t_outlet_charges_value; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.t_outlet_charges_value TO prod_kelava;
GRANT ALL ON TABLE public.t_outlet_charges_value TO replicator;


--
-- Name: SEQUENCE t_outlet_charges_value_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.t_outlet_charges_value_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.t_outlet_charges_value_id_seq TO replicator;


--
-- Name: TABLE t_outlet_promo; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_outlet_promo TO replicator;


--
-- Name: SEQUENCE t_outlet_promo_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_outlet_promo_id_seq TO replicator;


--
-- Name: SEQUENCE t_outlet_queue_date_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_outlet_queue_date_id_seq TO replicator;


--
-- Name: TABLE t_outlet_queue_date; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_outlet_queue_date TO replicator;


--
-- Name: TABLE t_outlet_queue_date_number; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_outlet_queue_date_number TO replicator;


--
-- Name: SEQUENCE t_outlet_queue_date_number_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_outlet_queue_date_number_id_seq TO replicator;


--
-- Name: TABLE t_payment; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_payment TO replicator;


--
-- Name: TABLE t_payment_callback_response; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_payment_callback_response TO replicator;


--
-- Name: SEQUENCE t_payment_callback_response_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_payment_callback_response_id_seq TO replicator;


--
-- Name: SEQUENCE t_payment_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_payment_id_seq TO replicator;


--
-- Name: TABLE t_product_outlet_movement; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_product_outlet_movement TO replicator;


--
-- Name: SEQUENCE t_product_materialoutlet_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_product_materialoutlet_id_seq TO replicator;


--
-- Name: TABLE t_product_outlet_stock; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.t_product_outlet_stock TO prod_kelava;
GRANT ALL ON TABLE public.t_product_outlet_stock TO replicator;


--
-- Name: SEQUENCE t_product_outlet_stock_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.t_product_outlet_stock_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.t_product_outlet_stock_id_seq TO replicator;


--
-- Name: TABLE t_promo; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_promo TO replicator;


--
-- Name: SEQUENCE t_promo_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_promo_id_seq TO replicator;


--
-- Name: TABLE t_purchase_order; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_purchase_order TO replicator;


--
-- Name: SEQUENCE t_purchase_order_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_purchase_order_id_seq TO replicator;


--
-- Name: TABLE t_registration; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.t_registration TO prod_kelava;
GRANT ALL ON TABLE public.t_registration TO replicator;


--
-- Name: SEQUENCE t_registration_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.t_registration_id_seq TO prod_kelava;
GRANT ALL ON SEQUENCE public.t_registration_id_seq TO replicator;


--
-- Name: SEQUENCE t_road_plan_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_road_plan_id_seq TO replicator;


--
-- Name: TABLE t_road_plan; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_road_plan TO replicator;


--
-- Name: SEQUENCE t_road_plan_approval_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_road_plan_approval_id_seq TO replicator;


--
-- Name: TABLE t_road_plan_approval; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_road_plan_approval TO replicator;


--
-- Name: SEQUENCE t_road_plan_sales_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_road_plan_sales_id_seq TO replicator;


--
-- Name: TABLE t_road_plan_sales; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_road_plan_sales TO replicator;


--
-- Name: SEQUENCE t_sales_order_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_order_id_seq TO replicator;


--
-- Name: TABLE t_sales_order; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_order TO replicator;


--
-- Name: TABLE t_sales_order_delivery; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_order_delivery TO replicator;


--
-- Name: SEQUENCE t_sales_order_delivery_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_order_delivery_id_seq TO replicator;


--
-- Name: TABLE t_sales_order_delivery_item; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_order_delivery_item TO replicator;


--
-- Name: SEQUENCE t_sales_order_delivery_item_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_order_delivery_item_id_seq TO replicator;


--
-- Name: TABLE t_sales_order_delivery_item_status; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_order_delivery_item_status TO replicator;


--
-- Name: SEQUENCE t_sales_order_delivery_item_status_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_order_delivery_item_status_id_seq TO replicator;


--
-- Name: SEQUENCE t_sales_order_line_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_order_line_id_seq TO replicator;


--
-- Name: TABLE t_sales_order_line; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_order_line TO replicator;


--
-- Name: TABLE t_sales_order_status_history; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_order_status_history TO replicator;


--
-- Name: SEQUENCE t_sales_order_status_history_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_order_status_history_id_seq TO replicator;


--
-- Name: SEQUENCE t_sales_outlet_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_outlet_id_seq TO replicator;


--
-- Name: TABLE t_sales_outlet; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_outlet TO replicator;


--
-- Name: SEQUENCE t_sales_target_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_target_id_seq TO replicator;


--
-- Name: TABLE t_sales_target; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_target TO replicator;


--
-- Name: TABLE t_sales_target_area; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_target_area TO replicator;


--
-- Name: SEQUENCE t_sales_target_area_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_target_area_id_seq TO replicator;


--
-- Name: SEQUENCE t_sales_target_company_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_target_company_id_seq TO replicator;


--
-- Name: TABLE t_sales_target_company; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_target_company TO replicator;


--
-- Name: TABLE t_sales_target_month; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_target_month TO replicator;


--
-- Name: SEQUENCE t_sales_target_month_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_target_month_id_seq TO replicator;


--
-- Name: TABLE t_sales_target_product; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_target_product TO replicator;


--
-- Name: SEQUENCE t_sales_target_product_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_target_product_id_seq TO replicator;


--
-- Name: TABLE t_sales_target_salesman; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_target_salesman TO replicator;


--
-- Name: SEQUENCE t_sales_target_salesman_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_target_salesman_id_seq TO replicator;


--
-- Name: TABLE t_sales_target_segment; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_target_segment TO replicator;


--
-- Name: SEQUENCE t_sales_target_segment_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_target_segment_id_seq TO replicator;


--
-- Name: TABLE t_sales_target_store; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_target_store TO replicator;


--
-- Name: SEQUENCE t_sales_target_store_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_target_store_id_seq TO replicator;


--
-- Name: TABLE t_sales_target_subarea; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_sales_target_subarea TO replicator;


--
-- Name: SEQUENCE t_sales_target_subarea_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_sales_target_subarea_id_seq TO replicator;


--
-- Name: SEQUENCE t_spg_result_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_spg_result_id_seq TO replicator;


--
-- Name: TABLE t_spg_result; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_spg_result TO replicator;


--
-- Name: SEQUENCE t_visit_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_visit_id_seq TO replicator;


--
-- Name: TABLE t_visit; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_visit TO replicator;


--
-- Name: SEQUENCE t_visit_data_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_visit_data_id_seq TO replicator;


--
-- Name: TABLE t_visit_data; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_visit_data TO replicator;


--
-- Name: SEQUENCE t_visit_product_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_visit_product_id_seq TO replicator;


--
-- Name: TABLE t_visit_product; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_visit_product TO replicator;


--
-- Name: TABLE t_withdraw; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_withdraw TO replicator;


--
-- Name: SEQUENCE t_withdraw_funds_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_withdraw_funds_id_seq TO replicator;


--
-- Name: TABLE t_withdraw_line; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.t_withdraw_line TO replicator;


--
-- Name: SEQUENCE t_withdraw_lin_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.t_withdraw_lin_id_seq TO replicator;


--
-- Name: TABLE temp; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.temp TO replicator;


--
-- Name: TABLE v_dashboard_contract; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_dashboard_contract TO replicator;


--
-- Name: TABLE v_dashboard_event; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_dashboard_event TO replicator;


--
-- Name: TABLE v_dashboard_manager_target; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_dashboard_manager_target TO replicator;


--
-- Name: TABLE v_dashboard_road_plan; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_dashboard_road_plan TO replicator;


--
-- Name: TABLE v_dashboard_sales_achievement; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_dashboard_sales_achievement TO replicator;


--
-- Name: TABLE v_dashboard_sales_target; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_dashboard_sales_target TO replicator;


--
-- Name: TABLE v_event; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_event TO replicator;


--
-- Name: TABLE v_event_marketing; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_event_marketing TO replicator;


--
-- Name: TABLE v_helper_delivery; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_helper_delivery TO replicator;


--
-- Name: TABLE v_sales_order_by_customer; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.v_sales_order_by_customer TO replicator;


--
-- Name: TABLE x_setting_application; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.x_setting_application TO replicator;


--
-- Name: SEQUENCE x_setting_application_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.x_setting_application_id_seq TO replicator;


--
-- Name: TABLE x_token_application; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON TABLE public.x_token_application TO replicator;


--
-- Name: SEQUENCE x_token_application_id_seq; Type: ACL; Schema: public; Owner: prod_kelava
--

GRANT ALL ON SEQUENCE public.x_token_application_id_seq TO replicator;


--
-- PostgreSQL database dump complete
--

