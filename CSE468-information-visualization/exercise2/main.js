// 기본 상태 관리 객체
const appState = {
  timeRange: null,
  selectedProduct: null,
  selectedRows: [],

  updateTimeRange(range) {
    this.timeRange = range;
    this.notifyVisualizations();
  },

  updateSelectedProduct(product) {
    this.selectedProduct = product;
    this.notifyVisualizations();
  },

  updateSelectedRows(rows) {
    this.selectedRows = rows;
    this.notifyVisualizations();
  },

  notifyVisualizations() {
    updateAreaChart(this);
    updateBarChart(this);
    updateDataTable(this);
  }
};

// 날짜 포맷 (04-Jan-22)
const parseDate = d3.timeParse("%d-%b-%y");

// 초기 데이터 로딩
d3.csv("chocolate_sales.csv").then(data => {
  // 전처리
  data.forEach(d => {
    d.Date = parseDate(d.Date);
    d.Amount = +d.Amount.replace(/[$,]/g, "").trim();
    d["Boxes Shipped"] = +d["Boxes Shipped"];
  });

  initAreaChart(data);
  initBarChart(data);
  initDataTable(data);
});

// Reset 버튼
document.getElementById("reset-btn").addEventListener("click", () => {
  appState.updateTimeRange(null);
  appState.updateSelectedProduct(null);
  appState.updateSelectedRows([]);
});

// 1. AREA CHART
function initAreaChart(data) {
  const monthlyData = d3.rollups(data, v => d3.sum(v, d => d.Amount), d => d3.timeMonth(d.Date));
  monthlyData.sort((a, b) => a[0] - b[0]);

  const margin = { top: 50, right: 20, bottom: 80, left: 60 };
  const width = 600 - margin.left - margin.right;
  const height = 400 - margin.top - margin.bottom;
  const contextHeight = 60;

  const container = d3.select("#area-chart");

  // 설명 문구
  container.insert("p", "svg")
    .text("📌 Drag on the chart below to select a time range and filter the dashboard.")
    .style("font-size", "14px")
    .style("margin", "5px 0 10px 0")
    .style("color", "#444");

  const svg = container.append("svg")
    .attr("width", width + margin.left + margin.right)
    .attr("height", height + margin.top + margin.bottom + contextHeight);

  const g = svg.append("g").attr("transform", `translate(${margin.left},${margin.top})`);

  const x = d3.scaleTime()
    .domain(d3.extent(monthlyData, d => d[0]))
    .range([0, width]);

  const y = d3.scaleLinear()
    .domain([0, d3.max(monthlyData, d => d[1])])
    .nice()
    .range([height, 0]);

  const area = d3.area()
    .x(d => x(d[0]))
    .y0(height)
    .y1(d => y(d[1]));

  // 제목
  svg.append("text")
    .attr("x", (width + margin.left + margin.right) / 2)
    .attr("y", 30)
    .attr("text-anchor", "middle")
    .attr("font-size", "16px")
    .attr("font-weight", "bold")
    .text("Monthly Total Sales Over Time");

  // 메인 영역 차트
  g.append("path")
    .datum(monthlyData)
    .attr("fill", "#69b3a2")
    .attr("d", area);

  // x축
  g.append("g")
    .attr("transform", `translate(0,${height})`)
    .call(d3.axisBottom(x).tickFormat(d3.timeFormat("%b %Y")))
    .selectAll("text")
    .attr("transform", "rotate(-45)")
    .style("text-anchor", "end");

  // y축
  g.append("g").call(d3.axisLeft(y));

  // y축 레이블
  svg.append("text")
    .attr("transform", "rotate(-90)")
    .attr("x", - (height + margin.top + margin.bottom) / 2)
    .attr("y", 15)
    .attr("text-anchor", "middle")
    .attr("font-size", "12px")
    .text("Amount ($)");

  // context chart
  const context = svg.append("g")
    .attr("transform", `translate(${margin.left},${margin.top + height + 20})`);

  const contextX = x.copy();
  const contextY = d3.scaleLinear()
    .domain(y.domain())
    .range([contextHeight, 0]);

  const contextArea = d3.area()
    .x(d => contextX(d[0]))
    .y0(contextHeight)
    .y1(d => contextY(d[1]));

  context.append("path")
    .datum(monthlyData)
    .attr("fill", "#ccc")
    .attr("d", contextArea);

  // brush
  const brush = d3.brushX()
    .extent([[0, 0], [width, contextHeight]])
    .on("end", (event) => {
      if (!event.selection) return;
      const [x0, x1] = event.selection.map(contextX.invert);
      appState.updateTimeRange([x0, x1]);
    });

  context.append("g").attr("class", "brush").call(brush);

  // 업데이트 함수
  window.updateAreaChart = (state) => {
    if (state.timeRange) {
      x.domain(state.timeRange);
    } else {
      x.domain(d3.extent(monthlyData, d => d[0]));
    }
    g.select("path").transition().duration(500).attr("d", area);
    g.select("g").call(d3.axisBottom(x).tickFormat(d3.timeFormat("%b %Y")));
  };
}


// 2. BAR CHART
function initBarChart(data) {
  const productSales = d3.rollups(data, v => d3.sum(v, d => d.Amount), d => d.Product);
  productSales.sort((a, b) => b[1] - a[1]);

  const margin = { top: 50, right: 30, bottom: 80, left: 80 };
  const width = 600 - margin.left - margin.right;
  const height = 400 - margin.top - margin.bottom;

  const container = d3.select("#bar-chart");

  // 안내 문구
  container.insert("p", "svg")
    .text("📌 Click a bar to filter the dashboard by product.")
    .style("font-size", "14px")
    .style("margin", "5px 0 10px 0")
    .style("color", "#444");

  const svg = container.append("svg")
    .attr("width", width + margin.left + margin.right)
    .attr("height", height + margin.top + margin.bottom)
    .append("g")
    .attr("transform", `translate(${margin.left},${margin.top})`);

  const x = d3.scaleBand()
    .domain(productSales.map(d => d[0]))
    .range([0, width])
    .padding(0.1);

  const y = d3.scaleLinear()
    .domain([0, d3.max(productSales, d => d[1])])
    .nice()
    .range([height, 0]);

  // 제목
  svg.append("text")
    .attr("x", width / 2)
    .attr("y", -20)
    .attr("text-anchor", "middle")
    .attr("font-size", "16px")
    .attr("font-weight", "bold")
    .text("Total Sales by Product");

  // x축
  svg.append("g")
    .attr("transform", `translate(0,${height})`)
    .call(d3.axisBottom(x))
    .selectAll("text")
    .attr("transform", "rotate(-45)")
    .style("text-anchor", "end");

  // y축
  svg.append("g")
    .call(d3.axisLeft(y));

  // y축 레이블
  svg.append("text")
    .attr("transform", "rotate(-90)")
    .attr("x", -height / 2)
    .attr("y", -50)
    .attr("text-anchor", "middle")
    .attr("font-size", "12px")
    .text("Amount ($)");

  // 툴팁 div
  const tooltip = d3.select("body")
    .append("div")
    .style("position", "absolute")
    .style("background", "#fff")
    .style("border", "1px solid #ccc")
    .style("padding", "6px 10px")
    .style("border-radius", "4px")
    .style("pointer-events", "none")
    .style("opacity", 0);

  // 막대 추가
  svg.selectAll("rect")
    .data(productSales)
    .enter().append("rect")
    .attr("x", d => x(d[0]))
    .attr("y", d => y(d[1]))
    .attr("width", x.bandwidth())
    .attr("height", d => height - y(d[1]))
    .attr("fill", "#888")
    .on("click", (event, d) => {
      appState.updateSelectedProduct(d[0]);
    })
    .on("mouseover", (event, d) => {
      tooltip.transition().duration(200).style("opacity", 0.9);
      tooltip.html(`<strong>${d[0]}</strong><br/>$${d[1].toLocaleString()}`)
        .style("left", (event.pageX + 10) + "px")
        .style("top", (event.pageY - 28) + "px");
    })
    .on("mouseout", () => {
      tooltip.transition().duration(200).style("opacity", 0);
    });

  // 상태 업데이트 함수
  window.updateBarChart = (state) => {
    svg.selectAll("rect")
      .attr("fill", d => state.selectedProduct === d[0] ? "#ff7f0e" : "#888");
  };
}


// 3. DATA TABLE
function initDataTable(data) {
  const tableDiv = d3.select("#datatable");
  const table = tableDiv.append("table");
  const thead = table.append("thead");
  const tbody = table.append("tbody");
  const paginationDiv = tableDiv.append("div").attr("class", "pagination");

  const columns = Object.keys(data[0]);
  let sortColumn = null;
  let sortAscending = true;
  const filters = {};

  let currentFiltered = data;
  let currentPage = 1;
  const rowsPerPage = 20;

  const header = thead.append("tr")
    .selectAll("th")
    .data(columns)
    .enter()
    .append("th")
    .style("cursor", "pointer")
    .on("click", (event, column) => {
      if (sortColumn === column) {
        sortAscending = !sortAscending;
      } else {
        sortColumn = column;
        sortAscending = true;
      }
      updateHeaderLabels();
      renderRows(currentFiltered);
    });

  thead.append("tr")
    .selectAll("th")
    .data(columns)
    .enter()
    .append("th")
    .append("input")
    .attr("type", "text")
    .attr("placeholder", "Filter...")
    .on("input", function (event, column) {
      filters[column] = this.value.trim().toLowerCase();
      updateDataTable(appState);
    });

  function updateHeaderLabels() {
    header.text(column => {
      if (column === sortColumn) {
        return column + (sortAscending ? " ▲" : " ▼");
      } else {
        return column;
      }
    });
  }

  function applyFilters(data) {
    return data.filter(row => {
      return Object.entries(filters).every(([col, query]) => {
        if (!query) return true;
        const val = row[col];
        if (val instanceof Date) {
          return d3.timeFormat("%Y-%m-%d")(val).toLowerCase().includes(query);
        }
        return String(val).toLowerCase().includes(query);
      });
    });
  }

  function renderPagination(totalRows) {
    const totalPages = Math.ceil(totalRows / rowsPerPage);
    paginationDiv.html("");

    if (totalPages <= 1) return;

    const nav = paginationDiv.append("div");

    nav.append("button")
      .text("Prev")
      .attr("disabled", currentPage === 1 ? true : null)
      .on("click", () => {
        if (currentPage > 1) {
          currentPage--;
          renderRows(currentFiltered);
        }
      });

    for (let i = 1; i <= totalPages; i++) {
    nav.append("button")
        .text(i)
        .attr("class", i === currentPage ? "active" : null)
        .on("click", () => {
        currentPage = i;
        renderRows(currentFiltered);
        });
    }


    nav.append("button")
      .text("Next")
      .attr("disabled", currentPage === totalPages ? true : null)
      .on("click", () => {
        if (currentPage < totalPages) {
          currentPage++;
          renderRows(currentFiltered);
        }
      });
  }

  function renderRows(filtered) {
    currentFiltered = filtered;

    if (sortColumn) {
      filtered = filtered.slice().sort((a, b) => {
        const aVal = a[sortColumn];
        const bVal = b[sortColumn];
        if (aVal === bVal) return 0;
        return (aVal > bVal ? 1 : -1) * (sortAscending ? 1 : -1);
      });
    }

    const totalRows = filtered.length;
    const start = (currentPage - 1) * rowsPerPage;
    const end = start + rowsPerPage;
    const pageRows = filtered.slice(start, end);

    tbody.selectAll("tr").remove();

    const rows = tbody.selectAll("tr")
      .data(pageRows)
      .enter()
      .append("tr")
      .on("click", (event, d) => {
        appState.updateSelectedRows([d]);
      });

    rows.selectAll("td")
      .data(d => columns.map(k => {
        const val = d[k];
        return val instanceof Date ? d3.timeFormat("%Y-%m-%d")(val) : val;
      }))
      .enter()
      .append("td")
      .text(d => d);

    renderPagination(totalRows);
  }

  window.updateDataTable = (state) => {
    let filtered = data;

    if (state.timeRange) {
      filtered = filtered.filter(d => d.Date >= state.timeRange[0] && d.Date <= state.timeRange[1]);
    }

    if (state.selectedProduct) {
      filtered = filtered.filter(d => d.Product === state.selectedProduct);
    }

    filtered = applyFilters(filtered);

    currentPage = 1;
    updateHeaderLabels();
    renderRows(filtered);
  };

  updateHeaderLabels();
  renderRows(data);
}
