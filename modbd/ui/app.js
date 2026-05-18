const API_BASE = 'http://localhost:5050/api';

const app = {
    init() {
        this.showSection('local-distributie');
        this.loadZone();
        setInterval(() => this.checkApi(), 5000);
    },

    showSection(id) {
        document.querySelectorAll('.view-section').forEach(sec => sec.style.display = 'none');
        document.getElementById(id).style.display = 'block';

        // Incarca datele corespunzatoare sectiunii selectate
        if (id === 'local-distributie') this.loadClienti();
        if (id === 'local-catalog') { this.loadItemsCore(); this.loadItemsExtra(); }
        if (id === 'local-vanzari-ro') this.loadFiseRo();
        if (id === 'local-vanzari-ext') this.loadFiseExt();
        if (id === 'global-items') this.loadItems();
        if (id === 'global-fise') this.loadFise();
        if (id === 'global-linii') this.loadLinii();
        if (id === 'mv-replicare') { 
            this.loadMvMaster(); 
            this.loadMvReplica(); 
            this.loadMvItemsMaster(); 
            this.loadMvItemsReplica(); 
        }
    },

    async checkApi() {
        try {
            const res = await fetch(`${API_BASE}/distributie/clienti?pageSize=1`).catch(() => null);
            document.getElementById('api-status').innerText = (res && res.ok) ? 'Status API: Online ✅' : 'Status API: Offline ❌';
        } catch (e) {
            document.getElementById('api-status').innerText = 'Status API: Offline ❌';
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

    // =====================================================================
    // LOCAL: DISTRIBUTIE — Clienti (CRUD complet)
    // =====================================================================

    async loadClienti(page = 1) {
        const tbody = document.getElementById('tbody-clienti');
        const searchInput = document.getElementById('search-clienti');
        const search = searchInput ? searchInput.value.trim() : '';
        try {
            const url = `${API_BASE}/distributie/clienti?page=${page}&pageSize=15` + (search ? `&search=${encodeURIComponent(search)}` : '');
            const res = await fetch(url);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.codClient}</td><td>${r.denumireClient}</td><td>${r.tipClient}</td>
                <td>${r.idZona}</td><td>${r.startDate ? new Date(r.startDate).toLocaleDateString('ro-RO') : '-'}</td>
                <td class="action-cell">
                    <button class="btn-edit" onclick="app.editClient(${r.id}, '${r.codClient}', '${r.denumireClient.replace(/'/g, "\\'").replace(/"/g, '&quot;')}', '${r.tipClient}', ${r.idZona})">✏️</button>
                    <button class="btn-delete" onclick="app.deleteClient(${r.id})">🗑️</button>
                </td>
            </tr>`).join('');
            this.renderPagination('pagination-clienti', result.page, result.totalPages, 'app.loadClienti');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="5">Eroare încărcare</td></tr>'; }
    },

    filterClientiTimer: null,
    filterClienti() {
        clearTimeout(this.filterClientiTimer);
        this.filterClientiTimer = setTimeout(() => this.loadClienti(1), 300);
    },

    editClient(id, cod, nume, tip, idZona) {
        document.getElementById('c-edit-id').value = id;
        document.getElementById('c-cod').value = cod;
        document.getElementById('c-nume').value = nume;
        document.getElementById('c-tip').value = tip;
        document.getElementById('c-zona').value = idZona;
        document.getElementById('form-clienti-title').innerText = 'Editează Client #' + id;
        document.getElementById('btn-cancel-client').style.display = 'block';
    },

    cancelEditClient() {
        document.getElementById('c-edit-id').value = '';
        document.getElementById('c-cod').value = '';
        document.getElementById('c-nume').value = '';
        document.getElementById('form-clienti-title').innerText = 'Adaugă Client';
        document.getElementById('btn-cancel-client').style.display = 'none';
    },

    async saveClient() {
        const editId = document.getElementById('c-edit-id').value;
        const body = {
            codClient: document.getElementById('c-cod').value,
            denumireClient: document.getElementById('c-nume').value,
            tipClient: document.getElementById('c-tip').value,
            idZona: parseInt(document.getElementById('c-zona').value) || 1
        };

        if (editId) {
            // UPDATE existent
            await fetch(`${API_BASE}/distributie/clienti/${editId}`, {
                method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
            });
            this.cancelEditClient();
        } else {
            // INSERT nou
            await fetch(`${API_BASE}/distributie/clienti`, {
                method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
            });
            document.getElementById('c-cod').value = '';
            document.getElementById('c-nume').value = '';
        }
        this.loadClienti();
    },

    async deleteClient(id) {
        if (!confirm('Sigur vrei să ștergi clientul #' + id + '?')) return;
        const response = await fetch(`${API_BASE}/distributie/clienti/${id}`, { method: 'DELETE' });
        if (!response.ok) {
            const errorData = await response.json().catch(() => ({}));
            alert(errorData.error || 'A apărut o eroare la ștergerea clientului.');
        }
        this.loadClienti();
    },

    // =====================================================================
    // LOCAL: CATALOG — Fragmente Verticale (items_core + items_extra)
    // =====================================================================

    async loadItemsCore(page = 1) {
        const tbody = document.getElementById('tbody-items-core');
        try {
            const res = await fetch(`${API_BASE}/catalog/items-core?page=${page}&pageSize=10`);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.itemCode}</td><td>${r.itemName}</td>
                <td>${r.brandId ?? '-'}</td><td>${r.seasonId ?? '-'}</td>
                <td>${r.itemTypeId ?? '-'}</td><td>${r.categoryId ?? '-'}</td>
                <td>${r.active === 1 ? 'Da' : 'Nu'}</td>
                <td class="action-cell">
                    <button class="btn-delete" onclick="app.deleteItemCore(${r.id})">🗑️</button>
                </td>
            </tr>`).join('');
            this.renderPagination('pagination-items-core', result.page, result.totalPages, 'app.loadItemsCore');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="5">Eroare încărcare</td></tr>'; }
    },

    async loadItemsExtra(page = 1) {
        const tbody = document.getElementById('tbody-items-extra');
        try {
            const res = await fetch(`${API_BASE}/catalog/items-extra?page=${page}&pageSize=10`);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${(r.itemDescription || '').substring(0, 50)}</td>
                <td>${r.vat ?? '-'}</td><td>${r.lastCostPrice ?? '-'}</td><td>${r.mainBarcode || '-'}</td>
                <td>${r.supplierCode || '-'}</td><td>${r.weight ?? '-'}</td><td>${r.um || '-'}</td>
            </tr>`).join('');
            this.renderPagination('pagination-items-extra', result.page, result.totalPages, 'app.loadItemsExtra');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="5">Eroare încărcare</td></tr>'; }
    },

    async deleteItemCore(id) {
        if (!confirm('Sigur vrei să ștergi produsul #' + id + '? (CASCADE va șterge și ITEMS_EXTRA)')) return;
        await fetch(`${API_BASE}/catalog/items-core/${id}`, { method: 'DELETE' });
        this.loadItemsCore();
        this.loadItemsExtra();
    },

    // =====================================================================
    // LOCAL: VANZARI — Fragmente Orizontale (fise_ro + fise_ext)
    // =====================================================================

    async loadFiseRo(page = 1) {
        const tbody = document.getElementById('tbody-fise-ro');
        const search = (document.getElementById('search-fise-ro')?.value || '').trim();
        try {
            const url = `${API_BASE}/vanzari/fise-ro?page=${page}&pageSize=15` + (search ? `&search=${encodeURIComponent(search)}` : '');
            const res = await fetch(url);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.nrDocument}</td><td>${r.tipDoc}</td><td>${r.docTypeXrp}</td>
                <td>${r.dataDocEfectiva ? new Date(r.dataDocEfectiva).toLocaleDateString('ro-RO') : '-'}</td>
                <td>${r.semn}</td><td>${r.moneda}</td><td>${r.amountDoc}</td><td>${r.amountDocRon}</td>
                <td>${r.codClient}</td><td>${r.denumireClient}</td><td>${r.clasaClient}</td>
            </tr>`).join('');
            this.renderPagination('pagination-fise-ro', result.page, result.totalPages, 'app.loadFiseRo');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="6">Eroare încărcare</td></tr>'; }
    },

    filterFiseRoTimer: null,
    filterFiseRo() {
        clearTimeout(this.filterFiseRoTimer);
        this.filterFiseRoTimer = setTimeout(() => this.loadFiseRo(1), 300);
    },

    async loadFiseExt(page = 1) {
        const tbody = document.getElementById('tbody-fise-ext');
        const search = (document.getElementById('search-fise-ext')?.value || '').trim();
        try {
            const url = `${API_BASE}/vanzari/fise-ext?page=${page}&pageSize=15` + (search ? `&search=${encodeURIComponent(search)}` : '');
            const res = await fetch(url);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.nrDocument}</td><td>${r.tipDoc}</td><td>${r.docTypeXrp}</td>
                <td>${r.dataDocEfectiva ? new Date(r.dataDocEfectiva).toLocaleDateString('ro-RO') : '-'}</td>
                <td>${r.semn}</td><td>${r.moneda}</td><td>${r.amountDoc}</td><td>${r.amountDocRon}</td>
                <td>${r.codClient}</td><td>${r.denumireClient}</td><td>${r.clasaClient}</td>
            </tr>`).join('');
            this.renderPagination('pagination-fise-ext', result.page, result.totalPages, 'app.loadFiseExt');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="6">Eroare încărcare</td></tr>'; }
    },

    filterFiseExtTimer: null,
    filterFiseExt() {
        clearTimeout(this.filterFiseExtTimer);
        this.filterFiseExtTimer = setTimeout(() => this.loadFiseExt(1), 300);
    },

    // =====================================================================
    // GLOBAL: Produse (V_ITEMS) + Facturi (V_FISE_CLIENTI)
    // =====================================================================

    async loadItems(page = 1) {
        const tbody = document.getElementById('tbody-items');
        try {
            const res = await fetch(`${API_BASE}/global/items?page=${page}&pageSize=15`);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.itemCode}</td><td>${r.itemName}</td>
                <td>${r.description || ''}</td><td>${r.active === 1 ? 'Da' : 'Nu'}</td>
            </tr>`).join('');
            this.renderPagination('pagination-items', result.page, result.totalPages, 'app.loadItems');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="5">Eroare încărcare</td></tr>'; }
    },

    async loadFise(page = 1) {
        const tbody = document.getElementById('tbody-fise');
        const search = (document.getElementById('search-fise')?.value || '').trim();
        try {
            const url = `${API_BASE}/global/fise?page=${page}&pageSize=15` + (search ? `&search=${encodeURIComponent(search)}` : '');
            const res = await fetch(url);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.nrDocument}</td><td>${r.docType}</td><td>${r.moneda}</td>
                <td>${r.amount}</td><td>${r.amountRon}</td>
                <td>${r.codClient}</td><td>${r.denumireClient}</td><td>${r.clasaClient}</td>
            </tr>`).join('');
            this.renderPagination('pagination-fise', result.page, result.totalPages, 'app.loadFise');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="5">Eroare încărcare</td></tr>'; }
    },

    filterFiseTimer: null,
    filterFise() {
        clearTimeout(this.filterFiseTimer);
        this.filterFiseTimer = setTimeout(() => this.loadFise(1), 300);
    },

    // =====================================================================
    // GLOBAL: Linii Documente (V_LINII_DOC)
    // =====================================================================

    async loadLinii(page = 1) {
        const tbody = document.getElementById('tbody-linii');
        try {
            const res = await fetch(`${API_BASE}/global/linii?page=${page}&pageSize=15`);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.docTypeXrp}</td><td>${r.nrDocument}</td><td>${r.itemCode}</td>
                <td>${r.itemQty ?? '-'}</td><td>${r.valoareFaraTva ?? '-'}</td>
                <td>${r.tva ?? '-'}</td><td>${r.valoareTotala ?? '-'}</td>
            </tr>`).join('');
            this.renderPagination('pagination-linii', result.page, result.totalPages, 'app.loadLinii');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="8">Eroare încărcare</td></tr>'; }
    },

    // =====================================================================
    // REPLICARE MV — Comparatie master vs replica
    // =====================================================================

    async loadMvMaster(page = 1) {
        const tbody = document.getElementById('tbody-mv-master');
        try {
            const res = await fetch(`${API_BASE}/distributie/clienti?page=${page}&pageSize=15`);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.codClient}</td><td>${r.denumireClient}</td><td>${r.tipClient}</td>
            </tr>`).join('');
            this.renderPagination('pagination-mv-master', result.page, result.totalPages, 'app.loadMvMaster');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="4">Eroare</td></tr>'; }
    },

    async loadMvReplica(page = 1) {
        const tbody = document.getElementById('tbody-mv-replica');
        try {
            const res = await fetch(`${API_BASE}/vanzari/mv-clienti?page=${page}&pageSize=15`);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.codClient}</td><td>${r.denumireClient}</td><td>${r.tipClient}</td>
            </tr>`).join('');
            this.renderPagination('pagination-mv-replica', result.page, result.totalPages, 'app.loadMvReplica');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="4">Eroare</td></tr>'; }
    },

    async loadMvItemsMaster(page = 1) {
        const tbody = document.getElementById('tbody-mv-items-master');
        try {
            const res = await fetch(`${API_BASE}/catalog/items-core?page=${page}&pageSize=15`);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.itemCode}</td><td>${r.itemName}</td><td>${r.active === 1 ? 'Da' : 'Nu'}</td>
            </tr>`).join('');
            this.renderPagination('pagination-mv-items-master', result.page, result.totalPages, 'app.loadMvItemsMaster');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="4">Eroare</td></tr>'; }
    },

    async loadMvItemsReplica(page = 1) {
        const tbody = document.getElementById('tbody-mv-items-replica');
        try {
            const res = await fetch(`${API_BASE}/vanzari/mv-items-core?page=${page}&pageSize=15`);
            const result = await res.json();
            tbody.innerHTML = result.data.map(r => `<tr>
                <td>${r.id}</td><td>${r.itemCode}</td><td>${r.itemName}</td><td>${r.active === 1 ? 'Da' : 'Nu'}</td>
            </tr>`).join('');
            this.renderPagination('pagination-mv-items-replica', result.page, result.totalPages, 'app.loadMvItemsReplica');
        } catch (e) { tbody.innerHTML = '<tr><td colspan="4">Eroare</td></tr>'; }
    },

    async refreshMv() {
        const status = document.getElementById('mv-status');
        status.innerText = '⏳ Se actualizează MV-urile...';
        try {
            const res = await fetch(`${API_BASE}/admin/refresh-mv`, { method: 'POST' });
            if (!res.ok) {
                const data = await res.json().catch(() => ({}));
                status.innerHTML = `<span style="color:red">❌ ${data.error || 'Eroare la refresh'}</span>`;
            } else {
                const data = await res.json();
                status.innerHTML = `<span style="color:green">✅ ${data.message}</span>`;
            }
            this.loadMvMaster();
            this.loadMvReplica();
            this.loadMvItemsMaster();
            this.loadMvItemsReplica();
        } catch (e) {
            status.innerHTML = '<span style="color:red">❌ Eroare de rețea!</span>';
        }
    },

    // =====================================================================
    // FORMULARE: Adaugare produse si facturi
    // =====================================================================

    async addItem() {
        const body = {
            itemCode: document.getElementById('i-cod').value,
            itemName: document.getElementById('i-nume').value,
            description: document.getElementById('i-desc').value,
            active: parseInt(document.getElementById('i-activ').value)
        };
        await fetch(`${API_BASE}/global/items`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
        this.loadItems();
        document.getElementById('i-cod').value = '';
        document.getElementById('i-nume').value = '';
        document.getElementById('i-desc').value = '';
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
    },

    // =====================================================================
    // UTILITARE: Paginare
    // =====================================================================

    renderPagination(elementId, current, total, functionName) {
        const el = document.getElementById(elementId);
        if (!el) return;
        let html = '';
        if (total > 1) {
            html += `<button onclick="${functionName}(${current - 1})" ${current === 1 ? 'disabled' : ''}>&laquo; Ant</button>`;
            html += `<span class="page-info">Pagina ${current} / ${total}</span>`;
            html += `<button onclick="${functionName}(${current + 1})" ${current === total ? 'disabled' : ''}>Urm &raquo;</button>`;
        }
        el.innerHTML = html;
    }
};

document.addEventListener('DOMContentLoaded', () => app.init());
