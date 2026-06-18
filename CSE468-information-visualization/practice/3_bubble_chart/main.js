// 1. 차트 크기 설정
const margin = { top: 70, right: 70, bottom: 70, left: 70 };
const width = 600 - margin.left - margin.right;
const height = 400 - margin.top - margin.bottom;

// 2. SVG 생성
const svg = d3.select("#chart")
  .append("svg")
  .attr("width", width + margin.left + margin.right)
  .attr("height", height + margin.top + margin.bottom)
  .append("g")
  .attr("transform", `translate(${margin.left}, ${margin.top})`);

// 3. 데이터 불러오고 숫자로 변환
d3.csv("data.csv", d => {
  return {
    country: d.country,
    population: +d.population,  // 원래 csv 파일은 문자열이기 때문에 +를 이용하여 숫자로 변환
    gdp: +d.gdp
  };
}).then(data => {

  // 4. 스케일 설정
  const xScale = d3.scaleLinear()
    .domain([0, d3.max(data, d => d.gdp)])
    .range([0, width]);

  const yScale = d3.scaleLinear()
    .domain([0, d3.max(data, d => d.population)])
    .range([height, 0]);

  // ⭐️ 버블 크기용 scale
  const rScale = d3.scaleSqrt()
    .domain([0, d3.max(data, d => d.population)])  // domain이 0~최대 population
    .range([0, 40]);  // 가장 큰 버블 반지름 = 40px으로 매핑

  // 5. 축 추가
  svg.append("g")
    .attr("transform", `translate(0, ${height})`)  // x축 아래로
    .call(d3.axisBottom(xScale).tickFormat(d3.format(".2s")));  // 유효숫자 2자리. (.2f면 소수 둘째자리까지, d면 정수로)

  svg.append("g")
    .call(d3.axisLeft(yScale).tickFormat(d3.format(".2s")));

  // 6. 원(circle) 추가
  svg.selectAll("circle")
    .data(data)
    .enter()
    .append("circle")
    .attr("cx", d => xScale(d.gdp))
    .attr("cy", d => yScale(d.population))
    .attr("r", d => rScale(d.population))  // 인구수 기반 반지름
    .attr("fill", "#2b8cbe")
    .attr("opacity", 0.7)
    .attr("stroke", "#333");

  // 7. 라벨 (국가 이름)
  svg.selectAll(".name-text")              // ← "text"가 아닌 고유 클래스명 사용
    .data(data)
    .enter()
    .append("text")
    .attr("class", "text-label")            // ← 클래스명 지정
    .attr("x", d => xScale(d.gdp))
    .attr("y", d => yScale(d.population))
    .attr("dy", ".35em")
    .attr("text-anchor", "middle")
    .attr("font-size", "11px")
    .text(d => d.country);

  // 8. 축 라벨 추가
  svg.append("text")
    .attr("x", width / 2)
    .attr("y", height + 40)
    .attr("text-anchor", "middle")
    .attr("font-size", 14)
    .text("Population");

  svg.append("text")
    .attr("transform", "rotate(-90)")
    .attr("x", -height / 2)
    .attr("y", -40)
    .attr("text-anchor", "middle")
    .attr("font-size", 14)
    .text("GDP");
});
