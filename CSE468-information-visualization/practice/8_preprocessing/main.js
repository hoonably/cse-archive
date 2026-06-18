// 1. 외부 CSV 파일 불러오기
// - d3.csv는 기본적으로 모든 값을 string으로 불러오기 때문에 숫자 변환 필요
d3.csv("chocolate_sales.csv").then(data => {

  // 2. 데이터 구조 확인 (필드 이름 및 샘플)
  console.log("원본 데이터 샘플:", data[0]);

  // 3. 문자열에서 숫자 추출 전처리
  // - "$9,600,000" → 9600000
  // - "%" 표시 등도 제거해줄 수 있음
  const cleanedData = data.map(d => ({
    ...d,
    // 문자열에 포함된 특수문자 제거 후 숫자 변환
    // replace: "$", "," 등을 제거
    sales: +d.Sales.replace(/[\$,]/g, ""),           // "$9,600,000" → 9600000
    price: +d.UnitPrice.replace(/[\$,]/g, ""),       // "$1.99" → 1.99
    boxesSold: +d.BoxesSold.replace(/[,]/g, ""),     // "250,000" → 250000
    // 기타 항목들 필요시 추가 처리
  }));

  // 4. 유효 데이터 필터링
  const validData = cleanedData.filter(d =>
    !isNaN(d.sales) && !isNaN(d.price) && !isNaN(d.boxesSold)
  );

  // 5. 추가 계산 필드 생성
  // 예: 평균 매출 단가 = sales / boxesSold
  const processedData = validData.map(d => ({
    ...d,
    revenuePerBox: d.sales / d.boxesSold
  }));

  console.log("최종 데이터:", processedData);

  // 이후 drawBarChart(processedData) 등 사용
});

// 1. CSV 파일 불러오기
// - d3.csv()는 비동기 함수로, Promise를 반환한다
// - CSV는 모든 값을 기본적으로 문자열(string)로 읽기 때문에 숫자 처리 필요
d3.csv("../../data/owid-covid-data.csv").then(data => {

  // 2. 원본 데이터 확인 (초기 구조 파악)
  console.log("원본 데이터 예시:", data[0]);
  // 예상 필드: iso_code, continent, location, date, population, people_vaccinated, ...

  // 3. 필요한 컬럼만 있는 데이터만 남기기 (결측치 제거)
  // - 비어있는 문자열("", null, undefined 등)을 제거함
  // - 숫자형 필드는 숫자로 변환 가능한지도 확인해야 함
  let filteredData = data.filter(d =>
    d.iso_code &&
    d.continent &&
    d.location &&
    d.date &&
    d.population &&
    d.people_vaccinated &&
    d.people_fully_vaccinated
  );

  // 4. 숫자형 필드 형 변환 (문자열 → 숫자)
  // - d3.csv는 모든 데이터를 문자열(string)로 불러오므로 수치 연산 전에 반드시 변환해야 함
  filteredData = filteredData.map(d => ({
    ...d,
    population: +d.population,
    people_vaccinated: +d.people_vaccinated,
    people_fully_vaccinated: +d.people_fully_vaccinated,
    date: new Date(d.date) // 날짜 필드도 Date 객체로 변환
  }));

  // 5. 특정 대륙 필터링 (예: 아시아만)
  const asiaData = filteredData.filter(d => d.continent === "Asia");

  // 6. 백신 접종률 계산 (새로운 필드 생성)
  // - fully_vaccinated_rate: 전체 접종 완료 인구 비율
  // - partially_vaccinated_rate: 한 번만 맞은 사람 비율
  // - people_vaccinated_rate: 최소 1회 이상 접종자 비율
  const processedData = asiaData.map(d => ({
    ...d,
    fully_vaccinated_rate: (d.people_fully_vaccinated / d.population) * 100,
    partially_vaccinated_rate: ((d.people_vaccinated - d.people_fully_vaccinated) / d.population) * 100,
    people_vaccinated_rate: (d.people_vaccinated / d.population) * 100
  }));

  // 7. 이상치 제거 (100% 이상은 제거)
  const cleaned = processedData.filter(d => d.people_vaccinated_rate <= 100);

  // 8. 국가별 최신 데이터만 남기기
  // - 날짜가 가장 최근인 데이터 1개만 남김
  const latestByCountry = {};
  cleaned.forEach(d => {
    const iso = d.iso_code;
    if (!latestByCountry[iso] || latestByCountry[iso].date < d.date) {
      latestByCountry[iso] = d;
    }
  });
  const latestData = Object.values(latestByCountry);

  // 9. 정렬 및 상위 N개 추출 (예: 접종률 높은 순서 Top 15)
  const top15 = latestData
    .sort((a, b) => b.people_vaccinated_rate - a.people_vaccinated_rate)
    .slice(0, 15);

  console.log("최종 시각화 대상 데이터:", top15);

  // 이후 drawBarChart(top15) 등 시각화 함수로 넘기면 됨
});
