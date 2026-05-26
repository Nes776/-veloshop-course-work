// Конфигурация
const API_URL = 'http://localhost:8000';

// Корзина
let cart = JSON.parse(localStorage.getItem('cart')) || [];

// Текущий пользователь
let currentUser = JSON.parse(localStorage.getItem('currentUser')) || null;

// Вспомогательные функции
function saveCart() {
    localStorage.setItem('cart', JSON.stringify(cart));
    updateCartCount();
}

function updateCartCount() {
    const count = cart.reduce((sum, item) => sum + item.quantity, 0);
    const cartCountElement = document.getElementById('cartCount');
    if (cartCountElement) {
        cartCountElement.textContent = count;
    }
}

function updateAuthUI() {
    const authButtons = document.getElementById('authButtons');
    const userInfo = document.getElementById('userInfo');
    const userName = document.getElementById('userName');

    if (currentUser) {
        if (authButtons) authButtons.style.display = 'none';
        if (userInfo) {
            userInfo.style.display = 'flex';
            if (userName) userName.textContent = currentUser.full_name;
        }
    } else {
        if (authButtons) authButtons.style.display = 'flex';
        if (userInfo) userInfo.style.display = 'none';
    }
}

function checkAuth() {
    if (!currentUser) {
        alert('Пожалуйста, войдите в систему');
        showLoginModal();
        return false;
    }
    return true;
}
// API вызовы
async function apiRequest(endpoint, method = 'GET', body = null) {
    const options = {
        method: method,
        headers: {
            'Content-Type': 'application/json',
        }
    };

    if (body) {
        options.body = JSON.stringify(body);
    }

    try {
        const response = await fetch(`${API_URL}${endpoint}`, options);
        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.detail || 'Ошибка запроса');
        }

        return data;
    } catch (error) {
        console.error('API Error:', error);
        throw error;
    }
}
// Товары
async function loadProducts() {
    const productsList = document.getElementById('productsList');
    if (!productsList) return;

    productsList.innerHTML = '<div class="loading">Загрузка...</div>';

    try {
        let url = '/products';
        const params = new URLSearchParams();

        const type = document.getElementById('filterType')?.value;
        const brand = document.getElementById('filterBrand')?.value;
        const minPrice = document.getElementById('minPrice')?.value;
        const maxPrice = document.getElementById('maxPrice')?.value;

        if (type && type !== '') params.append('type', type);
        if (brand && brand !== '') params.append('brand', brand);
        if (minPrice) params.append('min_price', minPrice);
        if (maxPrice) params.append('max_price', maxPrice);

        if (params.toString()) {
            url += '?' + params.toString();
        }

        const products = await apiRequest(url);

        if (products.length === 0) {
            productsList.innerHTML = '<div class="loading">Товары не найдены</div>';
            return;
        }

        productsList.innerHTML = products.map(product => `
            <div class="product-card">
                <a href="product.html?id=${product.id}" style="text-decoration: none; color: inherit;">
                    <h3>${product.name}</h3>
                </a>
                <div class="brand">${product.brand}</div>
                <div class="price">${product.price.toLocaleString()} ₽</div>
                <div class="stock">В наличии: ${product.stock_quantity} шт.</div>
                <p>${(product.description || '').substring(0, 100)}${(product.description || '').length > 100 ? '...' : ''}</p>
                <button onclick="event.stopPropagation(); addToCart(${product.id}, '${product.name}', ${product.price})">
                     В корзину
                </button>
                <a href="product.html?id=${product.id}" class="details-link">Подробнее →</a>
            </div>
        `).join('');

    } catch (error) {
        console.error('Ошибка:', error);
        productsList.innerHTML = '<div class="loading">Ошибка загрузки товаров</div>';
    }
}

async function loadBrands() {
    try {
        const products = await apiRequest('/products');
        const brands = [...new Set(products.map(p => p.brand))];

        const brandSelect = document.getElementById('filterBrand');
        if (brandSelect) {
            brands.forEach(brand => {
                const option = document.createElement('option');
                option.value = brand;
                option.textContent = brand;
                brandSelect.appendChild(option);
            });
        }
    } catch (error) {
        console.error('Ошибка загрузки брендов:', error);
    }
}
// Корзина
function addToCart(productId, name, price) {
    const existingItem = cart.find(item => item.product_id === productId);

    if (existingItem) {
        existingItem.quantity++;
    } else {
        cart.push({
            product_id: productId,
            name: name,
            price: price,
            quantity: 1
        });
    }

    saveCart();
    alert(`${name} добавлен в корзину!`);
}

function renderCart() {
    const cartItems = document.getElementById('cartItems');
    const totalPriceSpan = document.getElementById('totalPrice');

    if (!cartItems) return;

    if (cart.length === 0) {
        cartItems.innerHTML = '<div class="loading">Корзина пуста</div>';
        if (totalPriceSpan) totalPriceSpan.textContent = '0';
        return;
    }

    let total = 0;

    cartItems.innerHTML = cart.map(item => {
        const itemTotal = item.price * item.quantity;
        total += itemTotal;

        return `
            <div class="cart-item">
                <div class="cart-item-info">
                    <h3>${item.name}</h3>
                    <div>${item.price.toLocaleString()} ₽</div>
                </div>
                <div class="cart-item-quantity">
                    <button onclick="updateQuantity(${item.product_id}, -1)">-</button>
                    <span>${item.quantity}</span>
                    <button onclick="updateQuantity(${item.product_id}, 1)">+</button>
                </div>
                <div class="cart-item-price">${itemTotal.toLocaleString()} ₽</div>
                <button class="remove-btn" onclick="removeFromCart(${item.product_id})">Удалить</button>
            </div>
        `;
    }).join('');

    if (totalPriceSpan) totalPriceSpan.textContent = total.toLocaleString();
}

function updateQuantity(productId, delta) {
    const item = cart.find(item => item.product_id === productId);
    if (item) {
        item.quantity += delta;
        if (item.quantity <= 0) {
            cart = cart.filter(i => i.product_id !== productId);
        }
        saveCart();
        renderCart();
    }
}

function removeFromCart(productId) {
    cart = cart.filter(item => item.product_id !== productId);
    saveCart();
    renderCart();
}

async function checkout() {
    if (!checkAuth()) return;

    if (cart.length === 0) {
        alert('Корзина пуста');
        return;
    }

    const address = prompt('Введите адрес доставки:');
    if (!address) return;

    const items = cart.map(item => ({
        product_id: item.product_id,
        quantity: item.quantity
    }));

    try {
        const result = await apiRequest(`/orders?user_id=${currentUser.id}`, 'POST', {
            shipping_address: address,
            items: items
        });

        alert('Заказ успешно оформлен!');
        cart = [];
        saveCart();
        window.location.href = 'orders.html';

    } catch (error) {
        alert('Ошибка оформления заказа: ' + error.message);
    }
}
// Заказы

async function loadOrders() {
    const ordersList = document.getElementById('ordersList');
    if (!ordersList) return;

    if (!checkAuth()) return;

    ordersList.innerHTML = '<div class="loading">Загрузка...</div>';

    try {
        const orders = await apiRequest(`/orders?user_id=${currentUser.id}`);

        if (orders.length === 0) {
            ordersList.innerHTML = '<div class="loading">У вас пока нет заказов</div>';
            return;
        }

        ordersList.innerHTML = orders.map(order => `
            <div class="order-card">
                <div class="order-header">
                    <strong>Заказ #${order.id}</strong>
                    <span>${new Date(order.order_date).toLocaleDateString()}</span>
                    <span class="order-status status-${order.status}">${getStatusText(order.status)}</span>
                </div>
                <div class="order-items">
                    ${order.items ? order.items.map(item =>
            `${item.product_name} x${item.quantity} - ${(item.quantity * item.price).toLocaleString()} ₽`
        ).join('<br>') : ''}
                </div>
                <div class="order-total">
                    Итого: ${order.total_amount.toLocaleString()} ₽
                </div>
            </div>
        `).join('');

    } catch (error) {
        ordersList.innerHTML = '<div class="loading">Ошибка загрузки заказов</div>';
    }
}

function getStatusText(status) {
    const statuses = {
        'pending': 'Ожидает',
        'confirmed': 'Подтверждён',
        'shipped': 'Отправлен',
        'delivered': 'Доставлен',
        'cancelled': 'Отменён'
    };
    return statuses[status] || status;
}

// Аутентификация

async function register() {
    const fullName = document.getElementById('regFullName')?.value;
    const email = document.getElementById('regEmail')?.value;
    const password = document.getElementById('regPassword')?.value;
    const phone = document.getElementById('regPhone')?.value;
    const address = document.getElementById('regAddress')?.value;

    if (!fullName || !email || !password) {
        alert('Заполните обязательные поля');
        return;
    }

    try {
        const result = await apiRequest('/register', 'POST', {
            email: email,
            password: password,
            full_name: fullName,
            phone: phone,
            address: address
        });

        alert('Регистрация успешна! Теперь войдите в систему');
        closeRegisterModal();
        showLoginModal();

    } catch (error) {
        alert('Ошибка регистрации: ' + error.message);
    }
}

async function login() {
    const email = document.getElementById('loginEmail')?.value;
    const password = document.getElementById('loginPassword')?.value;

    if (!email || !password) {
        alert('Введите email и пароль');
        return;
    }

    try {
        const result = await apiRequest('/login', 'POST', {
            email: email,
            password: password
        });

        currentUser = result.user;
        localStorage.setItem('currentUser', JSON.stringify(currentUser));
        updateAuthUI();
        closeLoginModal();
        alert(`Добро пожаловать, ${currentUser.full_name}!`);

        // Обновляем страницу если нужно
        if (window.location.pathname.includes('orders.html')) {
            loadOrders();
        }

    } catch (error) {
        alert('Ошибка входа: ' + error.message);
    }
}

function logout() {
    currentUser = null;
    localStorage.removeItem('currentUser');
    updateAuthUI();
    alert('Вы вышли из системы');
    window.location.href = 'index.html';
}

// Модальные окна
function showLoginModal() {
    const modal = document.getElementById('loginModal');
    if (modal) modal.style.display = 'block';
}

function closeLoginModal() {
    const modal = document.getElementById('loginModal');
    if (modal) modal.style.display = 'none';
}

function showRegisterModal() {
    const modal = document.getElementById('registerModal');
    if (modal) modal.style.display = 'block';
}

function closeRegisterModal() {
    const modal = document.getElementById('registerModal');
    if (modal) modal.style.display = 'none';
}

// Закрытие модальных окон при клике вне области
window.onclick = function (event) {
    const loginModal = document.getElementById('loginModal');
    const registerModal = document.getElementById('registerModal');
    if (event.target === loginModal) closeLoginModal();
    if (event.target === registerModal) closeRegisterModal();
}

// Инициализация
document.addEventListener('DOMContentLoaded', () => {
    updateAuthUI();
    updateCartCount();

    // Привязываем обработчики форм
    const loginForm = document.getElementById('loginForm');
    if (loginForm) {
        loginForm.addEventListener('submit', (e) => {
            e.preventDefault();
            login();
        });
    }

    const registerForm = document.getElementById('registerForm');
    if (registerForm) {
        registerForm.addEventListener('submit', (e) => {
            e.preventDefault();
            register();
        });
    }
});