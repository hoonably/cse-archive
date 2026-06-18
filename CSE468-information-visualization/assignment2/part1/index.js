// 기본 SVG 영역 정의
const width = 1000;
const height = 1000;

const svg = d3.select("body")
  .append("svg")
  .attr("width", width)
  .attr("height", height);

// ──────────── 기본 도형 추가 ─────────────

// 발 1
svg.append("ellipse")
    .attr("cx", 570)
    .attr("cy", 630)
    .attr("rx", 80)
    .attr("ry", 120)
    .attr("transform", "rotate(-45, 600, 600)")
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 8)  // 테두리 두께
    .attr("fill", "#D955AA");

// 발 2
svg.append("ellipse")
    .attr("cx", 450)
    .attr("cy", 690)
    .attr("rx", 80)
    .attr("ry", 120)
    .attr("transform", "rotate(-30, 450, 690)")
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 8)  // 테두리 두께
    .attr("fill", "#D955AA");

// 팔 1
svg.append("ellipse")
    .attr("cx", 350)
    .attr("cy", 370)
    .attr("rx", 65)
    .attr("ry", 100)
    .attr("transform", "rotate(-30, 350, 370)")
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 8)  // 테두리 두께
    .attr("fill", "#F2AED4");

// 팔 2
svg.append("ellipse")
    .attr("cx", 670)
    .attr("cy", 500)
    .attr("rx", 100)
    .attr("ry", 65)
    .attr("transform", "rotate(-20, 670, 500)")
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 8)  // 테두리 두께
    .attr("fill", "#F2AED4");

// 몸통
svg.append("circle")
    .attr("cx", 500)
    .attr("cy", 500)
    .attr("r", 200)
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 8)  // 테두리 두께
    .attr("fill", "#F2AED4");

// 눈 1
svg.append("ellipse")
    .attr("cx", 500)
    .attr("cy", 450)
    .attr("rx", 23)
    .attr("ry", 50)
    .attr("transform", "rotate(10, 600, 600)")
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 4)  // 테두리 두께
    .attr("fill", "#7B78BF");

// 눈 2
svg.append("ellipse")
    .attr("cx", 600)
    .attr("cy", 460)
    .attr("rx", 20)
    .attr("ry", 48)
    .attr("transform", "rotate(10, 600, 600)")
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 4)  // 테두리 두께
    .attr("fill", "#7B78BF");

// 눈동자 1
svg.append("ellipse")
    .attr("cx", 500)
    .attr("cy", 440)
    .attr("rx", 20)
    .attr("ry", 32)
    .attr("transform", "rotate(10, 600, 600)")
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 4)  // 테두리 두께
    .attr("fill", "#000000");

// 눈동자 2
svg.append("ellipse")
    .attr("cx", 600)
    .attr("cy", 450)
    .attr("rx", 17)
    .attr("ry", 30)
    .attr("transform", "rotate(10, 600, 600)")
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 4)  // 테두리 두께
    .attr("fill", "#000000");

// 속눈동자 1
svg.append("ellipse")
.attr("cx", 532)
.attr("cy", 415)
.attr("rx", 19)
.attr("ry", 27)
.attr("transform", "rotate(10, 532, 415)")
.attr("stroke", "black")  // 테두리
.attr("stroke-width", 4)  // 테두리 두께
.attr("fill", "#FFFFFF");

// 속눈동자 2
svg.append("ellipse")
.attr("cx", 600)
.attr("cy", 440)
.attr("rx", 15)
.attr("ry", 25)
.attr("transform", "rotate(10, 600, 600)")
.attr("stroke", "black")  // 테두리
.attr("stroke-width", 4)  // 테두리 두께
.attr("fill", "#FFFFFF");


// 입
svg.append("ellipse")
    .attr("cx", 550)
    .attr("cy", 530)
    .attr("rx", 4)
    .attr("ry", 10)
    .attr("transform", "rotate(10, 600, 600)")
    .attr("stroke", "black")  // 테두리
    .attr("stroke-width", 4)  // 테두리 두께
    .attr("fill", "#000000");


// 볼
svg.append("ellipse")
.attr("cx", 660)
.attr("cy", 530)
.attr("rx", 22)
.attr("ry", 11)
.attr("transform", "rotate(10, 660, 530)")
.attr("fill", "#F483B8");

// 볼
svg.append("ellipse")
.attr("cx", 460)
.attr("cy", 480)
.attr("rx", 25)
.attr("ry", 12)
.attr("transform", "rotate(10, 460, 480)")
.attr("fill", "#F483B8");

// 마법봉
d3.xml("starrod.svg").then(data => {
    const importedNode = document.importNode(data.documentElement, true);
  
    // 1. Kirby SVG 내부에 <g> 그룹을 만들고 transform 적용
    const group = d3.select("svg")  // Kirby가 있는 최상위 svg
      .append("g")
      .attr("transform", "translate(35, 160) scale(0.4) rotate(-20)");
  
    // 2. 그 그룹 안에 starrod의 <svg>를 붙이기
    group.node().appendChild(importedNode);
  });
  