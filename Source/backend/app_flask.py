from flask import Flask, request, jsonify
from flask_cors import CORS
import psycopg2
import psycopg2.extras
import os
from dotenv import load_dotenv
from functools import wraps

load_dotenv()

app = Flask(__name__)
CORS(app)  # Разрешаем запросы с фронтенда


# Подключение к БД
def get_db_connection():
    conn = psycopg2.connect(
        host="localhost",
        database="bikeshop",
        user="postgres",
        password="1234"
    )
    return conn


# Простой home-эндпоинт
@app.route('/')
def home():
    return jsonify({"message": "Veloshop API is running!"})


#ТОВАРЫ
@app.route('/products', methods=['GET'])
def get_products():
    # Получаем параметры фильтрации из URL
    product_type = request.args.get('type')
    brand = request.args.get('brand')
    min_price = request.args.get('min_price')
    max_price = request.args.get('max_price')

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    # Базовый запрос
    query = "SELECT * FROM products WHERE 1=1"
    params = []

    # Добавляем фильтры
    if product_type:
        query += " AND type = %s"
        params.append(product_type)
    if brand:
        query += " AND brand = %s"
        params.append(brand)
    if min_price:
        query += " AND price >= %s"
        params.append(float(min_price))
    if max_price:
        query += " AND price <= %s"
        params.append(float(max_price))

    query += " ORDER BY id"

    cur.execute(query, params)
    products = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify(products)


@app.route('/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM products WHERE id = %s", (product_id,))
    product = cur.fetchone()
    cur.close()
    conn.close()
    if product:
        return jsonify(product)
    return jsonify({"error": "Product not found"}), 404


#ПОЛЬЗОВАТЕЛИ
@app.route('/register', methods=['POST'])
def register():
    data = request.json
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        # Простое сохранение
        cur.execute(
            "INSERT INTO users (email, password_hash, full_name, phone, address) VALUES (%s, %s, %s, %s, %s)",
            (data['email'], data['password'], data['full_name'], data.get('phone'), data.get('address'))
        )
        conn.commit()
        return jsonify(
            {"message": "User registered", "user": {"email": data['email'], "full_name": data['full_name']}}), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 400
    finally:
        cur.close()
        conn.close()


@app.route('/login', methods=['POST'])
def login():
    data = request.json
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT id, email, full_name, role FROM users WHERE email = %s AND password_hash = %s",
                (data['email'], data['password']))
    user = cur.fetchone()
    cur.close()
    conn.close()
    if user:
        return jsonify({"message": "Login success", "user": user})
    return jsonify({"error": "Invalid credentials"}), 401


#ЗАКАЗЫ
@app.route('/orders', methods=['GET'])
def get_orders():
    user_id = request.args.get('user_id')
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT o.*, 
               json_agg(json_build_object('product_name', p.name, 'quantity', oi.quantity, 'price', oi.unit_price)) as items
        FROM orders o
        LEFT JOIN order_items oi ON o.id = oi.order_id
        LEFT JOIN products p ON oi.product_id = p.id
        WHERE o.user_id = %s
        GROUP BY o.id
        ORDER BY o.order_date DESC
    """, (user_id,))
    orders = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify(orders)


@app.route('/orders', methods=['POST'])
def create_order():
    data = request.json
    user_id = request.args.get('user_id')
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        # Создаем заказ
        cur.execute(
            "INSERT INTO orders (user_id, shipping_address) VALUES (%s, %s) RETURNING id",
            (user_id, data['shipping_address'])
        )
        order_id = cur.fetchone()[0]

        # Добавляем позиции
        for item in data['items']:
            cur.execute("SELECT price FROM products WHERE id = %s", (item['product_id'],))
            price = cur.fetchone()[0]
            cur.execute(
                "INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES (%s, %s, %s, %s)",
                (order_id, item['product_id'], item['quantity'], price)
            )
            # Вызываем функцию обновления остатков (PostgreSQL)
            cur.execute("SELECT update_stock(%s, %s)", (item['product_id'], item['quantity']))

        # Считаем итог
        cur.execute("SELECT calculate_order_total(%s)", (order_id,))
        conn.commit()
        return jsonify({"message": "Order created", "order_id": order_id}), 201
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 400
    finally:
        cur.close()
        conn.close()


if __name__ == '__main__':
    app.run(debug=True, port=8000)