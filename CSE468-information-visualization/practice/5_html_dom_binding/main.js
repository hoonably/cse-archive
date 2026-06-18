// 리스트용 연습 데이터 생성: [10, 11, 12, ..., 19]
let data = Array(10).fill(10).map((x, i) => x + i);

// body 요소 선택
let body = d3.select("body");

// ul 태그 추가
let ul = body.append("ul");

// li 요소를 데이터에 따라 생성
let li = ul.selectAll("li")
  .data(data)
  .enter()
  .append("li")
  .text(d => d)  // 텍스트 설정

  // class 설정: 짝수/홀수
  .attr("class", d => d % 2 === 0 ? "even" : "odd")

  // 스타일: 짝수는 빨강, 홀수는 파랑
  .style("color", d => d % 2 === 0 ? "red" : "blue");
