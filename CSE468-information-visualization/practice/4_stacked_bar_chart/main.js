// 1. 차트 크기 설정
const margin = { top: 50, right: 30, bottom: 50, left: 70 };
const width = 600 - margin.left - margin.right;
const height = 400 - margin.top - margin.bottom;

// 2. SVG 생성
const svg = d3.select("#chart")
  .append("svg")
  .attr("width", width + margin.left + margin.right)   // 전체 SVG 너비
  .attr("height", height + margin.top + margin.bottom) // 전체 SVG 높이
  .append("g")
  .attr("transform", `translate(${margin.left}, ${margin.top})`); // 내부 여백 반영

// 3. CSV 불러오기 및 데이터 정리
d3.csv("data.csv").then(rawData => {

  // 3-1. key 목록: "country", "year"를 제외한 항목들을 누적 key로 사용
  const keys = rawData.columns.slice(2);  // 예: ["A", "B", "C"]

  // 3-2. 숫자 변환 및 총합 필드 생성
  const data = rawData.map(d => {
    const totals = {};
    keys.forEach(k => totals[k] = +d[k]);  // 문자열을 숫자로 변환
    return {
      country: d.country,                 // 카테고리 기준
      year: d.year,                       // 필요 시 보관
      ...totals,
      total: d3.sum(keys, k => +d[k])     // 누적값 계산
    };
  });

  // 4. 스케일 정의

  // 4-1. x축: 국가 이름을 기준으로 하는 범주형(band) 스케일
  const xScale = d3.scaleBand()
    .domain(data.map(d => d.country))     // 모든 국가 이름을 도메인으로 설정
    .range([0, width])
    .padding(0.2);                        // 막대 사이 여백

  // 4-2. y축: 누적값 기준 최대치
  const yScale = d3.scaleLinear()
    .domain([0, d3.max(data, d => d.total)])  // 최대 누적값 기준
    .range([height, 0]);                      // y축은 위로 갈수록 값이 커지므로 반대로

  // 4-3. 색상 스케일: 각 항목별로 색상 부여
  const color = d3.scaleOrdinal()
    .domain(keys)
    .range(d3.schemeSet2);  // 보기 좋은 8가지 색상 세트

  // 5. d3.stack()을 이용한 누적 데이터 구조 생성
  const stackedData = d3.stack()
    .keys(keys)(data);  // 각 항목별로 [x0, x1] 범위 생성됨

  // 6. 누적 막대 그리기

  // 각 key 항목마다 그룹(<g>) 생성
  svg.selectAll("g.layer")
    .data(stackedData)
    .enter()
    .append("g")
    .attr("class", "layer")
    .attr("fill", d => color(d.key))  // key에 따라 색상 지정
    .selectAll("rect")
    .data(d => d)
    .enter()
    .append("rect")
    .attr("x", d => xScale(d.data.country))            // x 위치: 국가 이름 기반
    .attr("y", d => yScale(d[1]))                      // y 위치: 위쪽 경계
    .attr("height", d => yScale(d[0]) - yScale(d[1]))  // 높이 = 아래 - 위
    .attr("width", xScale.bandwidth());                // 막대 너비

  // 7. 축 추가

  // x축: 아래쪽에 배치
  svg.append("g")
    .attr("transform", `translate(0, ${height})`)
    .call(d3.axisBottom(xScale));

  // y축: 왼쪽에 배치
  svg.append("g")
    .call(d3.axisLeft(yScale).tickFormat(d3.format(".2s")));  // 축약형 숫자 포맷 (ex: 1.2k)

  // 8. 범례 추가

  const legend = svg.selectAll(".legend")
    .data(keys)
    .enter()
    .append("g")
    .attr("transform", (d, i) => `translate(${i * 80}, -30)`); // x 위치를 간격 두고 배치

  legend.append("rect")
    .attr("width", 12)
    .attr("height", 12)
    .attr("fill", d => color(d));

  legend.append("text")
    .attr("x", 15)
    .attr("y", 10)
    .text(d => d)
    .attr("font-size", "12px");
});
