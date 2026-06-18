// 📌 차트에 사용할 데이터: 나라별 값 정의
const data = [
  { country: "Korea", value: 23 },
  { country: "Japan", value: 45 },
  { country: "China", value: 67 },
  { country: "India", value: 38 },
  { country: "Nepal", value: 20 },
];

// 📐 차트의 여백(margin) 설정
const margin = { top: 30, right: 30, bottom: 50, left: 40 };
// 실제 차트가 그려질 너비와 높이 계산 (여백 제외)
const width = 600 - margin.left - margin.right;
const height = 400 - margin.top - margin.bottom;

// 📄 SVG 요소 생성 후, 그룹(g) 요소를 이동시켜 실제 그릴 영역 설정
const svg = d3.select("body")              // HTML body에 접근
  .append("svg")                            // svg 요소 추가
  .attr("width", width + margin.left + margin.right)   // 전체 너비 설정 (여백 포함)
  .attr("height", height + margin.top + margin.bottom) // 전체 높이 설정 (여백 포함)
  .append("g")                              // 실제 차트를 그릴 g 요소 추가
  .attr("transform", `translate(${margin.left},${margin.top})`); // g 그룹을 왼쪽/위쪽 여백만큼 이동

// 🧭 x축용 스케일 설정 (카테고리형 → 나라 이름)
const x = d3.scaleBand()                    // band scale: 막대 차트용
  .domain(data.map(d => d.country))         // x축에 표시할 도메인은 country 목록
  .range([0, width])                        // 출력 범위는 0 ~ 차트 너비
  .padding(0.2);                            // 막대 간격 설정

// 📏 y축용 스케일 설정 (값의 범위 → 픽셀 위치)
const y = d3.scaleLinear()                  // linear scale: 수치형 y값에 사용
  .domain([0, d3.max(data, d => d.value)])  // y축 도메인은 0부터 최대값까지
  .range([height, 0]);                      // 화면에서는 아래가 0이므로 위로 갈수록 값이 커짐

// 🔻 x축을 아래쪽에 추가
svg.append("g")
  .attr("transform", `translate(0, ${height})`) // x축은 SVG의 아래쪽에 위치
  .call(d3.axisBottom(x));                      // 실제 x축 눈금 그리기

// 🔺 y축을 왼쪽에 추가
svg.append("g")
  .call(d3.axisLeft(y));                        // 실제 y축 눈금 그리기

// 🟦 각 데이터를 바탕으로 막대(rect) 생성
svg.selectAll("rect")              // rect 요소들을 선택 (아직 없음)
  .data(data)                      // 데이터 바인딩
  .enter()                         // 데이터 개수만큼 요소 생성 준비
  .append("rect")                 // 실제로 rect 생성
  .attr("x", d => x(d.country))   // 각 나라의 x 위치 (scale 적용)
  .attr("y", d => y(d.value))     // y 위치: 값이 클수록 위쪽에 위치
  .attr("width", x.bandwidth())   // 막대 너비는 band 내부 간격으로 자동 계산됨
  .attr("height", d => height - y(d.value))  // 막대 높이 = 아래에서부터 얼마나 위로 올라가는지 계산
  .attr("fill", "#69b3a2")         // 기본 색상 지정

  // 🟡 마우스를 올렸을 때: 색상을 오렌지색으로 부드럽게 전환
  .on("mouseover", function(event, d) {
    d3.select(this)                 // 현재 선택한 막대
      .transition()                // 전환 애니메이션 시작
      .duration(200)              // 200ms 동안
      .attr("fill", "orange");    // 색상을 오렌지로 바꿈
  })

  // 🔵 마우스를 벗어났을 때: 원래 색으로 복귀
  .on("mouseout", function(event, d) {
    d3.select(this)
      .transition()
      .duration(200)
      .attr("fill", "#69b3a2");   // 기본색으로 복귀
  })

  // 🔴 막대를 클릭했을 때: 콘솔에 국가명과 값 출력
  .on("click", function(event, d) {
    console.log(`You clicked: ${d.country} (${d.value})`);
  });
