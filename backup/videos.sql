--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.5
-- Dumped by pg_dump version 9.6.5

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

SET search_path = public, pg_catalog;

DROP INDEX public.idx_videos_youtube_video_id;
DROP INDEX public.idx_videos_song_source_num;
DROP TABLE public.videos;
SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: videos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE videos (
    youtube_video_id text NOT NULL,
    song_source_num integer NOT NULL
);


--
-- Data for Name: videos; Type: TABLE DATA; Schema: public; Owner: -
--

COPY videos (youtube_video_id, song_source_num) FROM stdin;
5YABP0QTMxQ	94324
44tZddEjp5g	802116
4Dc5XBbcCeE	806412
wBoOu1WVUlY	814094
2up_Hybx_eE	823162
CfaMT7gh4Es	851608
2oiGCxh6SEA	916097
2aw7sBQLXcQ	919851
WxfXzywKzYs	970984
tOCIsy9tYJs	1065635
MwTZRfkIPDY	1107485
9XrH-oMPxnw	1150443
ULLAXfqiUGw	1185979
Na22GkXMiE4	1250805
iE6sZq4hwZ0	1285020
eZC08evVZAM	1406363
AH18FtrGbwo	1409187
cMFVtJJ9NNw	1695356
ECE2jR33VZM	1733800
s8BQUlhPR5w	1778381
z3pAS6eKvsc	1875659
-P3_aml2-gc	1891189
K2aByptv2ng	1912629
Ay4QoiOHbi0	1972087
ex-BKVSQ7sU	1991508
BIGhyK4ZIx8	2029160
jveJPT5A3B8	2054674
hlw9YNIPUiE	2056423
hlw9YNIPUiE	2056423
VEOMmAFW1DM	2090650
\.


--
-- Name: idx_videos_song_source_num; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_videos_song_source_num ON videos USING btree (song_source_num);


--
-- Name: idx_videos_youtube_video_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_videos_youtube_video_id ON videos USING btree (youtube_video_id);


--
-- PostgreSQL database dump complete
--

