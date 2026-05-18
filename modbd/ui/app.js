const API_BASE = 'http://localhost:5050/api';

const app = {
    init() {
        this.showSection('local-distributie');
        this.loadZone();
        setInterval(() => this.checkApi(), 3000);
    },

    showSection(id) {
        document.querySelectorAll('.view-section').forEach(sec => sec.style.display = 'none');
        document.getElementById(id).style.display = 'block';

        if (id === 'local-distributie') this.loadClienti();
        if (id === 'global-items') this.loadItems();
        if (id === 'global-fise') this.loadFise();
    },

    async checkApi() {
        try {
            const res = await fetch(`${API_BASE}/distributie/clienti?pageSize=1`).catch(() => null);
            document.getElementById('api-status').innerText = (res && res.ok) ? 'Status API: Online' : 'Status API: Offline';
        } catch (e) {
            document.getElementById('api-status').innerText = 'Status API: Offline';
        }
    },

    async loadZone() {
        const select = document.getElementById('c-zona');
        if (!select) return;
        try {
            const res = await fetch(`${API_BASE}/distributie/zone`);
            const data = await res.json();
            select.innerHTML = data.map(z => `<option value="${z.id}">${z.denZona}</option>`).join('');
        } catch (e) {
            select.innerHTML = '<option value="1">Zona Default</option>';
        }
    },

    async loadClienti(page = 1) {
        const tbody = document.getElementById('tbody-clienti');
        const searchInput = document.getElementById('search-clienti');
        const search = searchInput ? searchInput.value.trim() : '';
        try {
            const url = `${API_BASE}/distributie/clienti?page=${page}&pageSize=15` + (search ? `&search=${encodeURIComponent(search)}` : '');
            const res = await fetch(url);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr><td>${r.id}</td><td>${r.codClient}</td><td>${r.denumireClient}</td><td>${r.tipClient}</td></tr>`).join('');
            this.renderPagination('pagination-clienti', result.page, result.totalPages, 'app.loadClienti');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="4">Eroare încărcare</td></tr>'; }
    },

    filterClientiTimer: null,
    filterClienti() {
        clearTimeout(this.filterClientiTimer);
        this.filterClientiTimer = setTimeout(() => this.loadClienti(1), 300);
    },

    async loadItems(page = 1) {
        const tbody = document.getElementById('tbody-items');
        try {
            const res = await fetch(`${API_BASE}/global/items?page=${page}&pageSize=15`);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr><td>${r.id}</td><td>${r.itemCode}</td><td>${r.itemName}</td><td>${r.description || ''}</td><td>${r.active === 1 ? 'Da' : 'Nu'}</td></tr>`).join('');
            this.renderPagination('pagination-items', result.page, result.totalPages, 'app.loadItems');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="5">Eroare încărcare</td></tr>'; }
    },

    async loadFise(page = 1) {
        const tbody = document.getElementById('tbody-fise');
        const searchInput = document.getElementById('search-fise');
        const search = searchInput ? searchInput.value.trim() : '';
        try {
            const url = `${API_BASE}/global/fise?page=${page}&pageSize=15` + (search ? `&search=${encodeURIComponent(search)}` : '');
            const res = await fetch(url);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr><td>${r.id}</td><td>${r.nrDocument}</td><td>${r.docType}</td><td>${r.moneda}</td><td>${r.amount}</td></tr>`).join('');
            this.renderPagination('pagination-fise', result.page, result.totalPages, 'app.loadFise');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="5">Eroare încărcare</td></tr>'; }
    },

    filterFiseTimer: null,
    filterFise() {
        clearTimeout(this.filterFiseTimer);
        this.filterFiseTimer = setTimeout(() => this.loadFise(1), 300);
    },

    renderPagination(elementId, current, total, functionName) {
        const el = document.getElementById(elementId);
        if (!el) return;
        let html = '';
        if (total > 1) {
            html += `<button onclick="${functionName}(${current - 1})" ${current === 1 ? 'disabled' : ''}>&laquo; Ant</button>`;
            html += `<span style="margin: 0 10px; align-self: center; font-size: 0.9em; color: #4b5563;"> Pagina ${current} / ${total} </span>`;
            html += `<button onclick="${functionName}(${current + 1})" ${current === total ? 'disabled' : ''}>Urm &raquo;</button>`;
        }
        el.innerHTML = html;
    },


    async addClient() {
        const body = {
            codClient: document.getElementById('c-cod').value,
            denumireClient: document.getElementById('c-nume').value,
            tipClient: document.getElementById('c-tip').value,
            idZona: parseInt(document.getElementById('c-zona').value) || 1
        };
        await fetch(`${API_BASE}/distributie/clienti`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
        this.loadClienti();
        document.getElementById('c-cod').value = ''; document.getElementById('c-nume').value = '';
    },

    async addItem() {
        const body = {
            itemCode: document.getElementById('i-cod').value,
            itemName: document.getElementById('i-nume').value,
            description: document.getElementById('i-desc').value,
            active: parseInt(document.getElementById('i-activ').value)
        };
        await fetch(`${API_BASE}/global/items`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
        this.loadItems();
        document.getElementById('i-cod').value = ''; document.getElementById('i-nume').value = ''; document.getElementById('i-desc').value = '';
    },

    async addFisa() {
        const body = {
            nrDocument: document.getElementById('f-nr').value,
            docType: 'INV',
            moneda: document.getElementById('f-moneda').value,
            amount: parseFloat(document.getElementById('f-val').value)
        };
        await fetch(`${API_BASE}/global/fise`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
        this.loadFise();
        document.getElementById('f-nr').value = '';
    }
};

document.addEventListener('DOMContentLoaded', () => app.init());
