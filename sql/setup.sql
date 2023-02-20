-- psql -h 127.0.0.1 -p 5432 -U ec -d ec -f sql/setup.sql

CREATE TABLE users (
  id serial NOT NULL,
  name varchar(50) NOT NULL,
  zipcode char(8) NOT NULL,
  address1 varchar(50) NOT NULL,
  address2 varchar(50) NOT NULL,
  email varchar(50) NOT NULL,
  password varchar(50) NOT NULL,
  payment char(1) NOT NULL,
  PRIMARY KEY(id), UNIQUE(email)
);

CREATE TABLE products (
  id serial NOT NULL,
  name varchar(50) NOT NULL,
  image varchar(50) NOT NULL,
  description text NOT NULL;
  PRIMARY KEY(id)
);

CREATE TABLE product_variation (
  id serial NOT NULL,
  content varchar(50) NOT NULL,
  price integer NOT NULL,
  product_id integer NOT NULL,
  PRIMARY KEY(id)
);

CREATE TABLE orders (
  id serial NOT NULL,
  user_id integer NOT NULL,
  total integer NOT NULL,
  created_at timestamp NOT NULL,
  PRIMARY KEY(id)
);

CREATE TABLE order_details (
  id serial NOT NULL,
  order_id integer NOT NULL,
  price integer NOT NULL,
  PRIMARY KEY(id)
);

CREATE TABLE likes (
  id serial NOT NULL,
  user_id integer NOT NULL,
  product_id integer NOT NULL,
  PRIMARY KEY(id)
);