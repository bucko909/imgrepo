--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: hotlink_stats; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE hotlink_stats (
    image_id integer NOT NULL,
    referrer_url text NOT NULL,
    hotlink_count integer NOT NULL,
    hotlink_limit integer,
    goatse_count integer NOT NULL,
    initial_hotlink_time bigint NOT NULL
);


--
-- Name: image_postings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE image_postings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: image_postings; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE image_postings (
    id integer DEFAULT nextval('image_postings_id_seq'::regclass) NOT NULL,
    image_id integer NOT NULL,
    line_id integer NOT NULL,
    url text NOT NULL,
    "time" integer NOT NULL
);


--
-- Name: image_postsold; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE image_postsold (
    image_id integer NOT NULL,
    line_id integer NOT NULL,
    url text NOT NULL,
    id integer NOT NULL
);


--
-- Name: image_tags; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE image_tags (
    image_id integer NOT NULL,
    tag_id integer NOT NULL,
    ip text NOT NULL,
    tag_time bigint
);


--
-- Name: image_visits; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE image_visits (
    image_id integer NOT NULL,
    "time" bigint NOT NULL,
    visit_key text NOT NULL
);


--
-- Name: images_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE images_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: images; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE images (
    id integer DEFAULT nextval('images_id_seq'::regclass) NOT NULL,
    local_filename text NOT NULL,
    local_thumbname text NOT NULL,
    md5sum text NOT NULL,
    thumbnail_width integer NOT NULL,
    thumbnail_height integer NOT NULL,
    image_width integer NOT NULL,
    image_height integer NOT NULL,
    image_type text NOT NULL,
    fullviews integer DEFAULT 0 NOT NULL,
    rating integer DEFAULT 0 NOT NULL,
    size integer,
    thumbnail_size integer,
    on_s3 boolean DEFAULT false NOT NULL
);


--
-- Name: ips; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE ips (
    ip text NOT NULL,
    name text
);


--
-- Name: irc_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE irc_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: irc_lines; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE irc_lines (
    id integer DEFAULT nextval('irc_lines_id_seq'::regclass) NOT NULL,
    "time" bigint NOT NULL,
    nick text NOT NULL,
    mask text NOT NULL,
    channel text,
    text text NOT NULL
);


--
-- Name: rating_raters; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE rating_raters (
    image_id integer NOT NULL,
    sess_id integer NOT NULL
);


--
-- Name: rating_ratings; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE rating_ratings (
    image_id integer NOT NULL,
    ip text NOT NULL,
    rating integer NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE sessions (
    id integer DEFAULT nextval('sessions_id_seq'::regclass) NOT NULL,
    start_time bigint NOT NULL,
    ip text NOT NULL,
    admin integer
);


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE tags (
    id integer DEFAULT nextval('tags_id_seq'::regclass) NOT NULL,
    name text NOT NULL,
    type text NOT NULL,
    has_other_type integer DEFAULT 0 NOT NULL
);


--
-- Name: test; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE test (
    foo text
);


--
-- Name: upload_queue_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE upload_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: upload_queue; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE upload_queue (
    id integer DEFAULT nextval('upload_queue_id_seq'::regclass) NOT NULL,
    url text NOT NULL,
    line_id integer,
    success boolean,
    fail_reason text,
    attempted boolean DEFAULT false NOT NULL,
    image_posting_id integer
);


--
-- Name: image_postings_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY image_postings
    ADD CONSTRAINT image_postings_pkey PRIMARY KEY (id);


--
-- Name: image_postsold_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY image_postsold
    ADD CONSTRAINT image_postsold_pkey PRIMARY KEY (id);


--
-- Name: image_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY image_tags
    ADD CONSTRAINT image_tags_pkey PRIMARY KEY (image_id, tag_id);


--
-- Name: images_local_filename_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY images
    ADD CONSTRAINT images_local_filename_key UNIQUE (local_filename);


--
-- Name: images_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY images
    ADD CONSTRAINT images_pkey PRIMARY KEY (id);


--
-- Name: ips_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY ips
    ADD CONSTRAINT ips_pkey PRIMARY KEY (ip);


--
-- Name: irc_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY irc_lines
    ADD CONSTRAINT irc_lines_pkey PRIMARY KEY (id);


--
-- Name: rating_raters_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY rating_raters
    ADD CONSTRAINT rating_raters_pkey PRIMARY KEY (image_id, sess_id);


--
-- Name: sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: tags_name_type_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY tags
    ADD CONSTRAINT tags_name_type_key UNIQUE (name, type);


--
-- Name: tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: upload_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY upload_queue
    ADD CONSTRAINT upload_queue_pkey PRIMARY KEY (id);


--
-- Name: hotlink_stats_image_id_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX hotlink_stats_image_id_idx ON hotlink_stats USING btree (image_id);


--
-- Name: hotlink_stats_referrer_url_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX hotlink_stats_referrer_url_idx ON hotlink_stats USING btree (referrer_url);


--
-- Name: image_postings_image_id_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX image_postings_image_id_idx ON image_postings USING btree (image_id);


--
-- Name: image_postings_line_id_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX image_postings_line_id_idx ON image_postings USING btree (line_id);


--
-- Name: image_postings_time_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX image_postings_time_idx ON image_postings USING btree ("time");


--
-- Name: image_postings_time_image_id_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX image_postings_time_image_id_idx ON image_postings USING btree ("time", image_id);


--
-- Name: image_tags_image_id_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX image_tags_image_id_idx ON image_tags USING btree (image_id);


--
-- Name: image_tags_tag_id_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX image_tags_tag_id_idx ON image_tags USING btree (tag_id);


--
-- Name: image_visits_image_id_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX image_visits_image_id_idx ON image_visits USING btree (image_id);


--
-- Name: image_visits_visit_key_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX image_visits_visit_key_idx ON image_visits USING btree (visit_key);


--
-- Name: images_local_thumbname_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX images_local_thumbname_idx ON images USING btree (local_thumbname);


--
-- Name: images_md5sum_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX images_md5sum_idx ON images USING btree (md5sum);


--
-- Name: irc_lines_channel_time_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX irc_lines_channel_time_idx ON irc_lines USING btree (channel, "time");


--
-- Name: irc_lines_time_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX irc_lines_time_idx ON irc_lines USING btree ("time");


--
-- Name: rating_ratings_image_id_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX rating_ratings_image_id_idx ON rating_ratings USING btree (image_id);


--
-- PostgreSQL database dump complete
--

