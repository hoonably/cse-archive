// 기본 SVG 영역 정의
const width = 600;
const height = 400;

const svg = d3.select("#chart")
  .append("svg")
  .attr("width", width)
  .attr("height", height)
  .style("background-color", "#f5f5f5");

// ──────────── 기본 도형 추가 ─────────────

// ▒ Rectangle (사각형) : 왼쪽 위 꼭짓점 기준
svg.append("rect")
  .attr("x", 10)
  .attr("y", 10)
  .attr("width", 60)
  .attr("height", 40)
  .attr("fill", "blue");

// ● Circle (원) : 중심 좌표 + 반지름
svg.append("circle")
  .attr("cx", 100)
  .attr("cy", 30)
  .attr("r", 20)
  .attr("fill", "green");

// ◐ Ellipse (타원) : 중심 + x/y방향 반지름
svg.append("ellipse")
  .attr("cx", 160)
  .attr("cy", 30)
  .attr("rx", 20)
  .attr("ry", 10)
  .attr("transform", "rotate(45, 160, 30)")  // cx, cy를 기준으로 45도 회전
  .attr("fill", "purple");

// ──────────── 선, 텍스트, 다각형 추가 ─────────────

// ─ Line (선): 시작점(x1,y1) → 끝점(x2,y2)
svg.append("line")
  .attr("x1", 200)
  .attr("y1", 10)
  .attr("x2", 250)
  .attr("y2", 50)
  .attr("stroke", "gray")
  .attr("stroke-width", 4);

// ✎ Text (텍스트)
svg.append("text")
  .attr("x", 300)
  .attr("y", 35)
  .attr("fill", "red")
  .attr("font-size", "16px")
  .text("SVG Text");

// ★ Polygon (다각형): 꼭짓점 좌표 나열
svg.append("polygon")
  .attr("points", "350,75 379,161 469,161 397,215 423,301 350,250 277,301 303,215 231,161 321,161")
  .attr("fill", "red")
  .attr("stroke", "blue")  // 테두리
  .attr("stroke-width", 3);  // 테두리 두께

// ⬡ Polygon (육각형 형태 예시)
svg.append("polygon")
  .attr("points", "500,75  558,137.5 558,262.5 500,325 442,262.6 442,137.5")
  .attr("fill", "lime")
  .attr("stroke", "blue")
  .attr("stroke-width", 3);
