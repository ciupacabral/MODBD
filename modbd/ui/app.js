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
        if (id === 'global-documents') this.initDocumentForm();
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
                <td>${r.endDate ? new Date(r.endDate).toLocaleDateString('ro-RO') : '-'}</td>
                <td class="action-cell">
                    <button class="btn-edit" onclick="app.editClient(${r.id}, '${r.codClient}', '${r.denumireClient.replace(/'/g, "\\'").replace(/"/g, '&quot;')}', '${r.tipClient}', ${r.idZona}, ${r.endDate ? `'${r.endDate}'` : 'null'})">✏️</button>
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

    editClient(id, cod, nume, tip, idZona, endDate) {
        document.getElementById('c-edit-id').value = id;
        document.getElementById('c-cod').value = cod;
        document.getElementById('c-nume').value = nume;
        document.getElementById('c-tip').value = tip;
        document.getElementById('c-zona').value = idZona;
        document.getElementById('c-end-date').value = endDate ? endDate.substring(0, 10) : '';
        document.getElementById('form-clienti-title').innerText = 'Editează Client #' + id;
        document.getElementById('btn-cancel-client').style.display = 'block';
    },

    cancelEditClient() {
        document.getElementById('c-edit-id').value = '';
        document.getElementById('c-cod').value = '';
        document.getElementById('c-nume').value = '';
        document.getElementById('c-end-date').value = '';
        document.getElementById('form-clienti-title').innerText = 'Adaugă Client';
        document.getElementById('btn-cancel-client').style.display = 'none';
    },

    async saveClient() {
        const editId = document.getElementById('c-edit-id').value;
        const endDateVal = document.getElementById('c-end-date').value;
        const body = {
            codClient: document.getElementById('c-cod').value,
            denumireClient: document.getElementById('c-nume').value,
            tipClient: document.getElementById('c-tip').value,
            idZona: parseInt(document.getElementById('c-zona').value) || 1,
            endDate: endDateVal ? endDateVal : null
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
                <td>${r.id}</td><td>${r.nrDocument}</td><td>${r.nrDocInitial || '-'}</td>
                <td>${r.tipDoc}</td><td>${r.docTypeXrp}</td>
                <td>${r.dataDocEfectiva ? new Date(r.dataDocEfectiva).toLocaleDateString('ro-RO') : '-'}</td>
                <td>${r.dataScad ? new Date(r.dataScad).toLocaleDateString('ro-RO') : '-'}</td>
                <td>${r.semn}</td><td>${r.moneda}</td><td>${r.amountDoc}</td><td>${r.amountDocRon}</td>
                <td>${r.plataPrin || '-'}</td>
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
                <td>${r.id}</td><td>${r.nrDocument}</td><td>${r.nrDocInitial || '-'}</td>
                <td>${r.tipDoc}</td><td>${r.docTypeXrp}</td>
                <td>${r.dataDocEfectiva ? new Date(r.dataDocEfectiva).toLocaleDateString('ro-RO') : '-'}</td>
                <td>${r.dataScad ? new Date(r.dataScad).toLocaleDateString('ro-RO') : '-'}</td>
                <td>${r.semn}</td><td>${r.moneda}</td><td>${r.amountDoc}</td><td>${r.amountDocRon}</td>
                <td>${r.plataPrin || '-'}</td>
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
                <td>${r.id}</td><td>${r.nrDocument}</td><td>${r.nrDocInitial || '-'}</td>
                <td>${r.docType}</td>
                <td>${r.dataDocEfectiva ? new Date(r.dataDocEfectiva).toLocaleDateString('ro-RO') : '-'}</td>
                <td>${r.dataScad ? new Date(r.dataScad).toLocaleDateString('ro-RO') : '-'}</td>
                <td>${r.moneda}</td>
                <td>${r.amount}</td><td>${r.amountRon}</td>
                <td>${r.plataPrin || '-'}</td>
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
                <td>${r.itemQty ?? '-'}</td>
                <td>${r.valoareFaraTva ?? '-'}</td>
                <td>${r.tva ?? '-'}</td>
                <td>${r.procentTva ?? '-'}</td>
                <td>${r.valoareTotala ?? '-'}</td>
                <td>${r.linieIsWithVat ?? '-'}</td>
                <td>${r.linieValoareFaraTva ?? '-'}</td>
                <td>${r.linieTva ?? '-'}</td>
                <td>${r.linieProcTva ?? '-'}</td>
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
        const nrInitial = document.getElementById('f-nr-initial').value.trim();
        const dataScad = document.getElementById('f-data-scad').value;
        const plataPrin = document.getElementById('f-plata-prin').value;
        const body = {
            nrDocument: document.getElementById('f-nr').value,
            nrDocInitial: nrInitial || null,
            docType: 'INV',
            moneda: document.getElementById('f-moneda').value,
            amount: parseFloat(document.getElementById('f-val').value),
            dataScad: dataScad || null,
            plataPrin: plataPrin || null
        };
        await fetch(`${API_BASE}/global/fise`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
        this.loadFise();
        document.getElementById('f-nr').value = '';
        document.getElementById('f-nr-initial').value = '';
        document.getElementById('f-data-scad').value = '';
        document.getElementById('f-plata-prin').value = '';
    },

    // =====================================================================
    // GLOBAL: Document cu Linii (INSERT atomic header + linii via INSERT ALL)
    // =====================================================================

    async initDocumentForm() {
        // Reset form
        const container = document.getElementById('linii-container');
        if (container && container.children.length === 0) {
            this.addLinieRow();
        }
        // Populeaza dropdown-ul de clienti
        const clientSelect = document.getElementById('d-client');
        if (clientSelect && clientSelect.options.length <= 1) {
            try {
                const res = await fetch(`${API_BASE}/distributie/clienti?page=1&pageSize=100`);
                const result = await res.json();
                clientSelect.innerHTML = '<option value="">— Selectează client —</option>' +
                    result.data.map(c => `<option value="${c.codClient}">${c.codClient} — ${c.denumireClient}</option>`).join('');
            } catch (e) {
                clientSelect.innerHTML = '<option value="">Eroare încărcare clienți</option>';
            }
        }
        // Populeaza datalist-ul cu coduri de produse
        const datalist = document.getElementById('items-datalist');
        if (datalist && datalist.children.length === 0) {
            try {
                const res = await fetch(`${API_BASE}/global/items?page=1&pageSize=200`);
                const result = await res.json();
                datalist.innerHTML = result.data.map(i => `<option value="${i.itemCode}">${i.itemName}</option>`).join('');
            } catch (e) { /* silent */ }
        }
    },

    addLinieRow() {
        const tbody = document.getElementById('linii-container');
        const tr = document.createElement('tr');
        tr.className = 'linie-row';
        tr.innerHTML = `
            <td><input type="text" class="l-item" list="items-datalist" placeholder="Cod produs" style="width: 130px;"></td>
            <td><input type="number" class="l-qty" step="0.01" value="1" style="width: 70px;" oninput="app.recalcSuma()"></td>
            <td><input type="number" class="l-val" step="0.01" value="0" style="width: 100px;" oninput="app.recalcSuma()"></td>
            <td><input type="number" class="l-tva" step="0.01" value="0" style="width: 90px;" oninput="app.recalcSuma()"></td>
            <td><input type="number" class="l-pct" step="0.01" placeholder="19" style="width: 70px;"></td>
            <td>
                <select class="l-wvat" style="width: 70px;">
                    <option value="">auto</option>
                    <option value="Y">Y</option>
                    <option value="N">N</option>
                </select>
            </td>
            <td><input type="number" class="l-lin-val" step="0.01" placeholder="(=doc)" style="width: 100px;"></td>
            <td><input type="number" class="l-lin-tva" step="0.01" placeholder="(=doc)" style="width: 90px;"></td>
            <td><input type="number" class="l-lin-pct" step="0.01" placeholder="(=doc)" style="width: 70px;"></td>
            <td class="l-total" style="font-weight: 600;">0.00</td>
            <td><button type="button" class="btn-delete" onclick="app.removeLinieRow(this)">🗑️</button></td>
        `;
        tbody.appendChild(tr);
        this.recalcSuma();
    },

    removeLinieRow(btn) {
        const tr = btn.closest('tr');
        tr.remove();
        this.recalcSuma();
    },

    recalcSuma() {
        let total = 0;
        document.querySelectorAll('#linii-container .linie-row').forEach(row => {
            const val = parseFloat(row.querySelector('.l-val').value) || 0;
            const tva = parseFloat(row.querySelector('.l-tva').value) || 0;
            const lineTotal = val + tva;
            row.querySelector('.l-total').innerText = lineTotal.toFixed(2);
            total += lineTotal;
        });
        document.getElementById('suma-linii').innerText = total.toFixed(2);
        document.getElementById('amount-doc').innerText = total.toFixed(2);
    },

    async saveDocument() {
        const status = document.getElementById('doc-status');
        status.innerHTML = '';

        const nrDocument = document.getElementById('d-nr').value.trim();
        const nrDocInitial = document.getElementById('d-nr-initial').value.trim();
        const moneda = document.getElementById('d-moneda').value;
        const codClient = document.getElementById('d-client').value;
        const dataScad = document.getElementById('d-data-scad').value;
        const plataPrin = document.getElementById('d-plata-prin').value;

        if (!nrDocument) {
            status.innerHTML = '<span style="color:red">❌ Nr Document obligatoriu</span>';
            return;
        }
        if (!codClient) {
            status.innerHTML = '<span style="color:red">❌ Selectează un client</span>';
            return;
        }

        const linii = [];
        let totalCalc = 0;
        const rows = document.querySelectorAll('#linii-container .linie-row');
        for (const row of rows) {
            const itemCode = row.querySelector('.l-item').value.trim();
            const itemQty = parseFloat(row.querySelector('.l-qty').value) || 0;
            const valoareFaraTva = parseFloat(row.querySelector('.l-val').value) || 0;
            const tva = parseFloat(row.querySelector('.l-tva').value) || 0;

            if (!itemCode) {
                status.innerHTML = '<span style="color:red">❌ Toate liniile trebuie să aibă un cod de produs</span>';
                return;
            }

            // Câmpurile opționale — trimitem null dacă userul nu a completat, ca să
            // lăsăm backend-ul să le deducă (procentTva din raportul TVA/val,
            // linie* = doc* etc.).
            const pctRaw = row.querySelector('.l-pct').value;
            const wvatRaw = row.querySelector('.l-wvat').value;
            const linValRaw = row.querySelector('.l-lin-val').value;
            const linTvaRaw = row.querySelector('.l-lin-tva').value;
            const linPctRaw = row.querySelector('.l-lin-pct').value;

            linii.push({
                itemCode,
                itemQty,
                valoareFaraTva,
                tva,
                procentTva: pctRaw !== '' ? parseFloat(pctRaw) : null,
                linieIsWithVat: wvatRaw || null,
                linieValoareFaraTva: linValRaw !== '' ? parseFloat(linValRaw) : null,
                linieTva: linTvaRaw !== '' ? parseFloat(linTvaRaw) : null,
                linieProcTva: linPctRaw !== '' ? parseFloat(linPctRaw) : null
            });
            totalCalc += valoareFaraTva + tva;
        }

        if (linii.length === 0) {
            status.innerHTML = '<span style="color:red">❌ Adaugă cel puțin o linie</span>';
            return;
        }

        const body = {
            nrDocument,
            nrDocInitial: nrDocInitial || null,
            docType: 'INV',
            moneda,
            amount: Math.round(totalCalc * 100) / 100,
            dataScad: dataScad || null,
            plataPrin: plataPrin || null,
            codClient,
            linii
        };

        status.innerHTML = '<span style="color:#0284c7">⏳ Se trimite documentul...</span>';
        try {
            const res = await fetch(`${API_BASE}/global/documents`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body)
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok) {
                status.innerHTML = `<span style="color:red">❌ ${data.error || 'Eroare la salvare'}</span>`;
                return;
            }
            status.innerHTML = `<span style="color:green">✅ Document salvat: ${data.nrDocument || nrDocument} (header + ${linii.length} linii într-o singură tranzacție)</span>`;
            // Reset form
            document.getElementById('d-nr').value = '';
            document.getElementById('d-nr-initial').value = '';
            document.getElementById('d-data-scad').value = '';
            document.getElementById('d-plata-prin').value = '';
            document.getElementById('linii-container').innerHTML = '';
            this.addLinieRow();
            this.recalcSuma();
        } catch (e) {
            status.innerHTML = `<span style="color:red">❌ Eroare de rețea: ${e.message}</span>`;
        }
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
