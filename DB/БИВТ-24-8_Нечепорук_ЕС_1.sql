--
-- PostgreSQL database dump
--

\restrict 4hCx8fC1irvKqDfVqmLDPiAFC7ZmrIbMgA3gmMZlg6vCMqyEtcbqZ6ee5HVT0Gd

-- Dumped from database version 18.0
-- Dumped by pg_dump version 18.0

-- Started on 2026-05-26 16:40:09

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 4 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- TOC entry 5048 (class 0 OID 0)
-- Dependencies: 4
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- TOC entry 236 (class 1255 OID 16488)
-- Name: advance_order_status(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.advance_order_status(IN p_order_id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE orders 
    SET status = CASE status
        WHEN 'pending' THEN 'confirmed'
        WHEN 'confirmed' THEN 'shipped'
        WHEN 'shipped' THEN 'delivered'
        ELSE status
    END
    WHERE id = p_order_id;
END;
$$;


ALTER PROCEDURE public.advance_order_status(IN p_order_id integer) OWNER TO postgres;

--
-- TOC entry 235 (class 1255 OID 16487)
-- Name: apply_discount(character varying, numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.apply_discount(IN p_product_type character varying, IN p_percent numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE products 
    SET price = price * (1 - p_percent / 100)
    WHERE type = p_product_type;
END;
$$;


ALTER PROCEDURE public.apply_discount(IN p_product_type character varying, IN p_percent numeric) OWNER TO postgres;

--
-- TOC entry 237 (class 1255 OID 16489)
-- Name: archive_old_orders(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.archive_old_orders(IN p_days integer DEFAULT 365)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE orders 
    SET status = 'archived'
    WHERE status = 'delivered' 
      AND order_date < CURRENT_DATE - p_days;
END;
$$;


ALTER PROCEDURE public.archive_old_orders(IN p_days integer) OWNER TO postgres;

--
-- TOC entry 232 (class 1255 OID 16484)
-- Name: calculate_order_total(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_order_total(p_order_id integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    total DECIMAL(10, 2);
BEGIN
    SELECT COALESCE(SUM(quantity * unit_price), 0) INTO total
    FROM order_items
    WHERE order_id = p_order_id;
    
    UPDATE orders SET total_amount = total WHERE id = p_order_id;
    RETURN total;
END;
$$;


ALTER FUNCTION public.calculate_order_total(p_order_id integer) OWNER TO postgres;

--
-- TOC entry 239 (class 1255 OID 16501)
-- Name: check_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    stock INTEGER;
BEGIN
    SELECT stock_quantity INTO stock FROM products WHERE id = NEW.product_id;
    IF stock < NEW.quantity THEN
        RAISE EXCEPTION 'Not enough stock for product %', NEW.product_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.check_stock() OWNER TO postgres;

--
-- TOC entry 234 (class 1255 OID 16486)
-- Name: get_user_stats(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_user_stats(p_user_id integer) RETURNS TABLE(total_orders bigint, total_spent numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(o.id)::BIGINT,
        COALESCE(SUM(o.total_amount), 0)
    FROM orders o
    WHERE o.user_id = p_user_id AND o.status != 'cancelled';
END;
$$;


ALTER FUNCTION public.get_user_stats(p_user_id integer) OWNER TO postgres;

--
-- TOC entry 238 (class 1255 OID 16499)
-- Name: log_price_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.log_price_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.price != NEW.price THEN
        INSERT INTO price_log (product_id, old_price, new_price)
        VALUES (NEW.id, OLD.price, NEW.price);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_price_change() OWNER TO postgres;

--
-- TOC entry 233 (class 1255 OID 16485)
-- Name: update_stock(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_stock(p_product_id integer, p_quantity integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE products 
    SET stock_quantity = stock_quantity - p_quantity
    WHERE id = p_product_id AND stock_quantity >= p_quantity;
    
    RETURN FOUND;
END;
$$;


ALTER FUNCTION public.update_stock(p_product_id integer, p_quantity integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 224 (class 1259 OID 16426)
-- Name: orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.orders (
    id integer NOT NULL,
    user_id integer NOT NULL,
    order_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(50) DEFAULT 'pending'::character varying,
    total_amount numeric(10,2) DEFAULT 0,
    shipping_address text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.orders OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 16479)
-- Name: monthly_sales; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.monthly_sales AS
 SELECT date_trunc('month'::text, order_date) AS month,
    count(DISTINCT id) AS orders_count,
    sum(total_amount) AS revenue
   FROM public.orders o
  WHERE ((status)::text <> ALL ((ARRAY['pending'::character varying, 'cancelled'::character varying])::text[]))
  GROUP BY (date_trunc('month'::text, order_date))
  ORDER BY (date_trunc('month'::text, order_date)) DESC;


ALTER VIEW public.monthly_sales OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 16447)
-- Name: order_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_items (
    id integer NOT NULL,
    order_id integer NOT NULL,
    product_id integer NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    CONSTRAINT order_items_quantity_check CHECK ((quantity > 0))
);


ALTER TABLE public.order_items OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16446)
-- Name: order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.order_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.order_items_id_seq OWNER TO postgres;

--
-- TOC entry 5049 (class 0 OID 0)
-- Dependencies: 225
-- Name: order_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.order_items_id_seq OWNED BY public.order_items.id;


--
-- TOC entry 223 (class 1259 OID 16425)
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.orders_id_seq OWNER TO postgres;

--
-- TOC entry 5050 (class 0 OID 0)
-- Dependencies: 223
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- TOC entry 228 (class 1259 OID 16474)
-- Name: popular_products; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.popular_products AS
SELECT
    NULL::integer AS id,
    NULL::character varying(255) AS name,
    NULL::character varying(100) AS brand,
    NULL::numeric(10,2) AS price,
    NULL::bigint AS total_sold,
    NULL::integer AS stock_quantity;


ALTER VIEW public.popular_products OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 16491)
-- Name: price_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.price_log (
    id integer NOT NULL,
    product_id integer,
    old_price numeric(10,2),
    new_price numeric(10,2),
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.price_log OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 16490)
-- Name: price_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.price_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.price_log_id_seq OWNER TO postgres;

--
-- TOC entry 5051 (class 0 OID 0)
-- Dependencies: 230
-- Name: price_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.price_log_id_seq OWNED BY public.price_log.id;


--
-- TOC entry 222 (class 1259 OID 16407)
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    brand character varying(100) NOT NULL,
    type character varying(100) NOT NULL,
    price numeric(10,2) NOT NULL,
    stock_quantity integer DEFAULT 0 NOT NULL,
    description text,
    image_url character varying(500),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT products_price_check CHECK ((price >= (0)::numeric)),
    CONSTRAINT products_stock_quantity_check CHECK ((stock_quantity >= 0))
);


ALTER TABLE public.products OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16406)
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.products_id_seq OWNER TO postgres;

--
-- TOC entry 5052 (class 0 OID 0)
-- Dependencies: 221
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- TOC entry 220 (class 1259 OID 16390)
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    full_name character varying(255) NOT NULL,
    phone character varying(50),
    address text,
    role character varying(50) DEFAULT 'customer'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.users OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 16469)
-- Name: user_order_summary; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.user_order_summary AS
 SELECT u.id,
    u.email,
    u.full_name,
    count(o.id) AS total_orders,
    COALESCE(sum(o.total_amount), (0)::numeric) AS total_spent
   FROM (public.users u
     LEFT JOIN public.orders o ON ((u.id = o.user_id)))
  GROUP BY u.id, u.email, u.full_name;


ALTER VIEW public.user_order_summary OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 16389)
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- TOC entry 5053 (class 0 OID 0)
-- Dependencies: 219
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- TOC entry 4860 (class 2604 OID 16450)
-- Name: order_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items ALTER COLUMN id SET DEFAULT nextval('public.order_items_id_seq'::regclass);


--
-- TOC entry 4855 (class 2604 OID 16429)
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- TOC entry 4861 (class 2604 OID 16494)
-- Name: price_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price_log ALTER COLUMN id SET DEFAULT nextval('public.price_log_id_seq'::regclass);


--
-- TOC entry 4852 (class 2604 OID 16410)
-- Name: products id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- TOC entry 4849 (class 2604 OID 16393)
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- TOC entry 5040 (class 0 OID 16447)
-- Dependencies: 226
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_items (id, order_id, product_id, quantity, unit_price) FROM stdin;
3	6	4	5	65990.00
6	8	1	2	35990.00
7	8	3	1	42000.00
8	9	1	1	34200.00
9	10	1	1	34200.00
10	12	1	2	34200.00
11	12	2	1	34200.00
\.


--
-- TOC entry 5038 (class 0 OID 16426)
-- Dependencies: 224
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (id, user_id, order_date, status, total_amount, shipping_address, created_at) FROM stdin;
3	2	2026-05-25 22:59:29.627958	pending	45000.00	СПб, Невский, 10	2026-05-25 22:59:29.627958
6	3	2026-05-25 23:37:55.550983	pending	329950.00	-	2026-05-25 23:37:55.550983
7	1	2026-05-01 10:30:00	delivered	0.00	Москва, ул. Ленина, 1	2026-05-25 23:41:51.848884
1	1	2026-05-25 22:59:29.627958	pending	0.00	Москва, ул. Ленина, 1	2026-05-25 22:59:29.627958
2	1	2026-05-25 22:59:29.627958	pending	0.00	Москва, ул. Ленина, 1	2026-05-25 22:59:29.627958
8	1	2026-05-15 14:30:00	delivered	113980.00	Москва, ул. Ленина, 1	2026-05-25 23:43:13.342278
9	4	2026-05-26 00:28:31.686384	pending	34200.00	г. Москва, ул. Ленина, д.10, кв.5	2026-05-26 00:28:31.686384
10	3	2026-05-26 13:37:31.419761	pending	34200.00	-	2026-05-26 13:37:31.419761
12	1	2026-05-26 16:21:00.773425	pending	102600.00	г. Москва, ул. Ленина, д.10, кв.5	2026-05-26 16:21:00.773425
\.


--
-- TOC entry 5042 (class 0 OID 16491)
-- Dependencies: 231
-- Data for Name: price_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.price_log (id, product_id, old_price, new_price, changed_at) FROM stdin;
1	1	35000.00	31500.00	2026-05-25 22:59:29.627958
2	4	45000.00	40500.00	2026-05-25 22:59:29.627958
3	2	42990.00	38000.00	2026-05-25 23:39:48.014857
4	1	35990.00	38000.00	2026-05-25 23:39:48.014857
5	3	49990.00	44991.00	2026-05-26 00:20:48.992506
6	5	58990.00	53091.00	2026-05-26 00:20:48.992506
7	6	45990.00	41391.00	2026-05-26 00:20:48.992506
8	7	79990.00	71991.00	2026-05-26 00:20:48.992506
9	8	37990.00	34191.00	2026-05-26 00:20:48.992506
10	9	52990.00	47691.00	2026-05-26 00:20:48.992506
11	10	69990.00	62991.00	2026-05-26 00:20:48.992506
12	11	47990.00	43191.00	2026-05-26 00:20:48.992506
13	12	39990.00	35991.00	2026-05-26 00:20:48.992506
14	13	54990.00	49491.00	2026-05-26 00:20:48.992506
15	14	44990.00	40491.00	2026-05-26 00:20:48.992506
16	4	65990.00	59391.00	2026-05-26 00:20:48.992506
17	2	38000.00	34200.00	2026-05-26 00:20:48.992506
18	1	38000.00	34200.00	2026-05-26 00:20:48.992506
\.


--
-- TOC entry 5036 (class 0 OID 16407)
-- Dependencies: 222
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.products (id, name, brand, type, price, stock_quantity, description, image_url, created_at) FROM stdin;
15	Trek FX 2 Disc	Trek	hybrid	47990.00	9	Гибрид для города и лёгкого бездорожья. Алюминиевая рама, дисковые тормоза, 2x8 скоростей, шины Bontrager H2.	https://avatars.mds.yandex.net/i?id=1p6n0o7r2q3g4b5c6d7e8f9g0h1i2j3k4l5m6n7o-56789012	2026-05-25 23:10:38.792426
16	Trek FX 3 Disc	Trek	hybrid	59990.00	6	Продвинутый гибрид. Карбоновая вилка, гидравлические тормоза, 2x10 скоростей, более агрессивная геометрия.	https://avatars.mds.yandex.net/i?id=2q7o1p8s3r4h5c6d7e8f9g0h1i2j3k4l5m6n7o8p-67890123	2026-05-25 23:10:38.792426
17	Merida Crossway 100	Merida	hybrid	42990.00	15	Универсальный городской велосипед. Рама из алюминия, вилка Suntour NEX, шины Schwalbe CX Comp. Комфорт каждый день.	https://avatars.mds.yandex.net/i?id=3r8p2q9t4s5i6d7e8f9g0h1i2j3k4l5m6n7o8p9q-78901234	2026-05-25 23:10:38.792426
18	Merida Crossway 300	Merida	hybrid	54990.00	8	Гибрид для активных. Гидравлические тормоза, 2x9 скоростей, улучшенная вилка. Плавный ход и контроль.	https://avatars.mds.yandex.net/i?id=4s9q3r0u5t6j7e8f9g0h1i2j3k4l5m6n7o8p9q0r-89012345	2026-05-25 23:10:38.792426
19	Giant Escape 2	Giant	hybrid	38990.00	18	Лёгкий городской гибрид. ALUXX рама, 3x7 скоростей, V-Brake тормоза. Простота и надёжность.	https://avatars.mds.yandex.net/i?id=5t0r4s1v6u7k8f9g0h1i2j3k4l5m6n7o8p9q0r1s-90123456	2026-05-25 23:10:38.792426
20	Giant Escape 1	Giant	hybrid	49990.00	10	Спортивный гибрид. 2x8 скоростей, дисковые механические тормоза, шины Giant Sport. Уверенность на любом покрытии.	https://avatars.mds.yandex.net/i?id=6u1s5t2w7v8l9g0h1i2j3k4l5m6n7o8p9q0r1s2t-01234567	2026-05-25 23:10:38.792426
3	Trek Marlin 5	Trek	mountain	44991.00	8	Легендарный хардтейл от Trek. Рама Alpha Silver Aluminum, 2x8 трансмиссия, блокировка вилки, шины Bontrager. Отличный старт в мир MTB.	https://avatars.mds.yandex.net/i?id=9d4b8c5f0e1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c-34567890	2026-05-25 23:10:38.792426
5	Merida Big Nine 100	Merida	mountain	53091.00	7	Алюминиевая рама с технологией Smooth Welding, 29 колеса, вилка Suntour XCR32, шины Maxxis. Быстрый и маневренный.	https://avatars.mds.yandex.net/i?id=1f6d0e7h2g3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e-56789012	2026-05-25 23:10:38.792426
6	Cube Aim Pro	Cube	mountain	41391.00	12	Немецкое качество. Рама из алюминия 6061, вилка SR Suntour XCM, 2x9 скоростей, дисковые тормоза. Надёжный выбор для гор.	https://avatars.mds.yandex.net/i?id=2g7e1f8i3h4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f-67890123	2026-05-25 23:10:38.792426
7	Cube Attention SL	Cube	mountain	71991.00	3	Карбоновая вилка, усиленная рама, трансмиссия Shimano Deore 1x11, гидравлические тормоза Shimano. Профессиональный уровень.	https://avatars.mds.yandex.net/i?id=3h8f2g9j4i5e6f7a8b9c0d1e2f3a4b5c6d7e8f9g-78901234	2026-05-25 23:10:38.792426
8	Author Colorado 29	Author	mountain	34191.00	20	Чешский бренд. Рама из хромомолибденовой стали, 24 скорости, вилка Suntour, дисковые механические тормоза. Классика MTB.	https://avatars.mds.yandex.net/i?id=4i9g3h0k5j6f7a8b9c0d1e2f3a4b5c6d7e8f9g0h-89012345	2026-05-25 23:10:38.792426
9	Cannondale Trail 8	Cannondale	mountain	47691.00	6	SmartForm C3 Alloy рама, вилка SR Suntour XCT, 2x8 скоростей, шины Schwalbe. Отличная управляемость и комфорт.	https://avatars.mds.yandex.net/i?id=5j0h4i1l6k7a8b9c0d1e2f3a4b5c6d7e8f9g0h1i-90123456	2026-05-25 23:10:38.792426
10	Specialized Rockhopper	Specialized	mountain	62991.00	4	A1 Premium Aluminum рама, вилка SR Suntour XCM, 2x9 трансмиссия, гидравлические тормоза. Легенда в мире горных велосипедов.	https://avatars.mds.yandex.net/i?id=6k1i5j2m7l8b9c0d1e2f3a4b5c6d7e8f9g0h1i2j-01234567	2026-05-25 23:10:38.792426
11	Giant Talon 2	Giant	mountain	43191.00	9	ALUXX-Grade Aluminum рама, вилка SR Suntour XCT, 2x8 скоростей, дисковые тормоза. Надёжность и контроль на трассе.	https://avatars.mds.yandex.net/i?id=7l2j6k3n8m9c0d1e2f3a4b5c6d7e8f9g0h1i2j3k-12345678	2026-05-25 23:10:38.792426
12	Scott Aspect 950	Scott	mountain	35991.00	14	Легкая рама 6061铝合金, вилка Suntour XCT, 3x7 скоростей, V-Brake тормоза. Бюджетный вход в мир горных велосипедов.	https://avatars.mds.yandex.net/i?id=8m3k7l4o9n0d1e2f3a4b5c6d7e8f9g0h1i2j3k4l-23456789	2026-05-25 23:10:38.792426
13	Scott Aspect 930	Scott	mountain	49491.00	7	Улучшенная версия. Гидравлические дисковые тормоза, вилка Suntour XCR, 2x9 скоростей. Отличное соотношение цена-качество.	https://avatars.mds.yandex.net/i?id=9n4l8m5p0o1e2f3a4b5c6d7e8f9g0h1i2j3k4l5m-34567890	2026-05-25 23:10:38.792426
14	GT Avalanche Sport	GT	mountain	40491.00	11	Уникальная рама с технологией Triple Triangle, вилка Suntour XCT, 3x8 скоростей. Узнаваемый дизайн и надёжность.	https://avatars.mds.yandex.net/i?id=0o5m9n6q1p2f3a4b5c6d7e8f9g0h1i2j3k4l5m6n-45678901	2026-05-25 23:10:38.792426
4	Trek Marlin 7	Trek	mountain	59391.00	0	Горный велосипед с улучшенной вилкой RockShox Judy, 1x10 трансмиссия, гидравлические тормоза, внутренняя проводка. Покоряет любые трассы.	https://avatars.mds.yandex.net/i?id=0e5c9d6g1f2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d-45678901	2026-05-25 23:10:38.792426
1	Stels Navigator 700	Stels	mountain	34200.00	10	Горный велосипед с алюминиевой рамой, 24 скорости, амортизационная вилка SR Suntour, дисковые механические тормоза. Идеален для бездорожья и лесных трасс.	https://avatars.mds.yandex.net/i?id=7b2f6b3e8c9a4d5e6f7a8b9c0d1e2f3a4b5c6d7e-12345678	2026-05-25 23:10:38.792426
2	Stels Navigator 800	Stels	mountain	34200.00	9	Продвинутая модель с 27 скоростями, усиленная рама, гидравлические дисковые тормоза, профессиональная вилка Rockshox. Для опытных райдеров.	https://avatars.mds.yandex.net/i?id=8c3a7b4e9d0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b-23456789	2026-05-25 23:10:38.792426
\.


--
-- TOC entry 5034 (class 0 OID 16390)
-- Dependencies: 220
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, email, password_hash, full_name, phone, address, role, created_at) FROM stdin;
1	ivan@example.com	hash_123	Иван Петров	+7-901-123-4567	Москва, ул. Ленина, 1	customer	2026-05-25 22:59:29.627958
2	maria@example.com	hash_456	Мария Сидорова	+7-902-234-5678	СПб, Невский, 10	customer	2026-05-25 22:59:29.627958
3	e@mail.com	1234	Иванов Иван Иванович	1111	-	customer	2026-05-25 23:24:12.041965
4	testuser@example.com	123456	Тестовый Пользователь	+7-999-123-4567	г. Москва, ул. Тестовая, д.1	customer	2026-05-26 00:26:49.55584
5	user@example.com	123456	Иван Петров	+7-999-123-4567	г. Москва, ул. Ленина, 1	customer	2026-05-26 16:05:54.384022
\.


--
-- TOC entry 5054 (class 0 OID 0)
-- Dependencies: 225
-- Name: order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_items_id_seq', 11, true);


--
-- TOC entry 5055 (class 0 OID 0)
-- Dependencies: 223
-- Name: orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_id_seq', 12, true);


--
-- TOC entry 5056 (class 0 OID 0)
-- Dependencies: 230
-- Name: price_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.price_log_id_seq', 18, true);


--
-- TOC entry 5057 (class 0 OID 0)
-- Dependencies: 221
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_id_seq', 20, true);


--
-- TOC entry 5058 (class 0 OID 0)
-- Dependencies: 219
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 5, true);


--
-- TOC entry 4875 (class 2606 OID 16458)
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- TOC entry 4873 (class 2606 OID 16440)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- TOC entry 4877 (class 2606 OID 16498)
-- Name: price_log price_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price_log
    ADD CONSTRAINT price_log_pkey PRIMARY KEY (id);


--
-- TOC entry 4871 (class 2606 OID 16424)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- TOC entry 4867 (class 2606 OID 16405)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 4869 (class 2606 OID 16403)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 5031 (class 2618 OID 16477)
-- Name: popular_products _RETURN; Type: RULE; Schema: public; Owner: postgres
--

CREATE OR REPLACE VIEW public.popular_products AS
 SELECT p.id,
    p.name,
    p.brand,
    p.price,
    COALESCE(sum(oi.quantity), (0)::bigint) AS total_sold,
    p.stock_quantity
   FROM ((public.products p
     LEFT JOIN public.order_items oi ON ((p.id = oi.product_id)))
     LEFT JOIN public.orders o ON (((oi.order_id = o.id) AND ((o.status)::text <> 'cancelled'::text))))
  GROUP BY p.id
  ORDER BY COALESCE(sum(oi.quantity), (0)::bigint) DESC;


--
-- TOC entry 4882 (class 2620 OID 16502)
-- Name: order_items trigger_check_stock; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_check_stock BEFORE INSERT ON public.order_items FOR EACH ROW EXECUTE FUNCTION public.check_stock();


--
-- TOC entry 4881 (class 2620 OID 16500)
-- Name: products trigger_price_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_price_log AFTER UPDATE OF price ON public.products FOR EACH ROW EXECUTE FUNCTION public.log_price_change();


--
-- TOC entry 4879 (class 2606 OID 16459)
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- TOC entry 4880 (class 2606 OID 16464)
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- TOC entry 4878 (class 2606 OID 16441)
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


-- Completed on 2026-05-26 16:40:10

--
-- PostgreSQL database dump complete
--

\unrestrict 4hCx8fC1irvKqDfVqmLDPiAFC7ZmrIbMgA3gmMZlg6vCMqyEtcbqZ6ee5HVT0Gd

