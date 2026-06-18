console.log("hello world!") // You can see this in the browser console if you run the server correctly

d3.csv('../../data/owid-covid-data.csv')
    .then(data => {

        /*
        -------------------------------------------
        YOUR CODE STARTS HERE

        TASK 1 - Data Processing 

        TO-DO-LIST
        1. Exclude data that contain missing values on columns you need
        2. Exclude all data except the latest data for each country
        3. Sort the data by the life expectancy
        -------------------------------------------
        */

        //! 1. Exclude data that contain missing values on columns you need
        var processedData = data.filter(d => {
            return d.continent && d.location && d.date && d.population && d.life_expectancy && d.gdp_per_capita
        })
        console.log(processedData)

        // 형변환
        processedData = processedData.map(d => {
            return {
                continent: d.continent,
                location: d.location,
                date: d3.timeParse("%Y-%m-%d")(d.date),  // Date 객체
                population: Number(d.population),
                life_expectancy: Number(d.life_expectancy),
                gdp_per_capita: Number(d.gdp_per_capita)
            }
        })

        //! 2. Exclude all data except the latest data for each country
        let latestDataByCountry = {}; // 국가 기준으로 최신 데이터 저장할 객체
        processedData.forEach((d) => {
            // 기존 데이터가 없거나 현재 데이터의 날짜가 더 최신이면 교체
            if (!latestDataByCountry[d.location] || latestDataByCountry[d.location].date < d.date) {
                latestDataByCountry[d.location] = d;
            }
        });
        processedData = Object.values(latestDataByCountry); // 객체에서 값만 뽑아 배열로 변환
        console.log(processedData)  // 왜 이전꺼하면 얘도 정렬되지?

        //! 3. Sort the data by the life expectancy
        processedData = processedData.sort((a, b) => b.life_expectancy - a.life_expectancy)
        console.log(processedData)

        /*
        -------------------------------------------
        YOUR CODE ENDS HERE
        -------------------------------------------
        */

        drawBubbleChart(processedData)

    })
    .catch(error => {
        console.error(error);
    });

function drawBubbleChart(data) {

    // Canvas Size
    const margin = { top: 5, right: 450, bottom: 50, left: 120 },
        width = 1800 - margin.left - margin.right,
        height = 900 - margin.top - margin.bottom;

    // Define the position of the chart 
    const svg = d3.select("#chart")
        .append("svg")
        .attr('width', width + margin.left + margin.right)
        .attr('height', height + margin.top + margin.bottom)
        .append("g")
        .attr("transform", `translate(${margin.left},${margin.top})`);


    /*
    -------------------------------------------
    YOUR CODE STARTS HERE

    TASK 2 - Drawing Bubble Chart

    TO-DO-LIST
    1. Define a scale named xScale for x-axis
    2. Define a scale named yScale for y-axis
    3. Define a list named continentList that contains 
    4. Define a scale named cScale for color
    5. Define a scale named sScale for size of the bubbles
    6. Draw Bubbles
    -------------------------------------------
    */

    //! 1. Define a scale named xScale for x-axis
    // You should set the x-axis range from 0 to 110% of the highest GDP Per Capita with evenly spaced ticks.
    const xScale = d3.scaleLinear()
        .domain([0, d3.max(data, d=>d.gdp_per_capita) * 1.1])  // 최대값의 110%
        .range([0, width])

    //! 2. Define a scale named yScale for y-axis
    // You should set the y-axis range from 90% of the lowest life expectancy to 110% of the highest life expectancy with evenly spaced ticks.
    const yScale = d3.scaleLinear()
        .domain([d3.min(data, d=>d.life_expectancy) * 0.9, d3.max(data, d=>d.life_expectancy) * 1.1])
        .range([height, 0])

    //! 3. Define a list named continentList that contains
    // Make sure that the order of the continent follows the order it appears in the dataset. 
    // e.g.) If continent values in dataset appear like [Asia, Asia, Europe, Asia, Africa, Europe, Europe, Asia, Africa], the continentList must be [Asia, Europe, Africa]
    const continentList = [...new Set(data.map(d=>d.continent))];  // Set 사용

    //! 4. Define a scale named cScale for color
    // Color the bubbles differently depending on the continent with the color palette:
    // ['#cce1f2', '#a6f8c5', '#fbf7d5', '#e9cec7', '#f59dae', '#d2bef1']  
    const cScale = d3.scaleOrdinal()
        .domain(continentList)
        .range(['#cce1f2', '#a6f8c5', '#fbf7d5', '#e9cec7', '#f59dae', '#d2bef1'])

    //! 5. Define a scale named sScale for size of the bubbles
    // Your bubble’s radius should range from 5 to 50.
    // And your bubble’s area must be proportional to the population of the country.
    const sScale = d3.scaleSqrt()
        .domain(d3.extent(data, d=>d.population))
        .range([5, 50])  // 최소 -> 5px, 최대 -> 50px 반지름으로 매핑되게끔

    //! 6. Draw Bubbles
    // svg가 const이므로 수정불가해서 bubble로 그리기
    bubble = svg.append('g')
        .selectAll("dot")
        .data(data)  // 데이터 바인딩
        .enter()
    bubble.append("circle")
        .attr("cx", d => xScale(d.gdp_per_capita))
        .attr("cy", d => yScale(d.life_expectancy))
        .attr("r", d => sScale(d.population))
        .style("fill", d => cScale(d.continent))  // continent 기준 색상으로
        .attr("stroke", "black")  // 테두리 검정으로!!

    // Define the position of each axis
    const xAxis = d3.axisBottom(xScale);
    const yAxis = d3.axisLeft(yScale);

    // Draw axes 
    svg.append("g")
        .attr('class', 'x-axis')
        .attr('transform', `translate(0, ${height})`)
        .call(xAxis);

    svg.append("g")
        .attr('class', 'y-axis')
        .call(yAxis)

    // Add x-axis label 
    svg.append("text")
        .attr("text-anchor", "end")
        .attr("x", width)
        .attr("y", height + 40)
        .attr("font-size", 17)
        .text("GDP Per Capita");

    // Add y-axis label 
    svg.append("text")
        .attr("text-anchor", "end")
        .attr("x", 0)
        .attr("y", -60)
        .attr("font-size", 17)
        .text("Life Expectency")
        .attr("transform", "rotate(270)");

    // Add legend
    const size = 30
    svg.selectAll("legend")
        .data(continentList)
        .enter()
        .append("circle")
        .attr("cx", width + 100)
        .attr("cy", function (d, i) { return 10 + i * size })
        .attr("r", 10)
        .style("fill", function (d) { return cScale(d) })
        .attr("stroke", "black")

    // Add legend texts
    svg.selectAll("legend_label")
        .data(continentList)
        .enter()
        .append("text")
        .attr("x", width + 100 + size)
        .attr("y", function (d, i) { return i * size + (size / 2) })
        .text(function (d) { return d })
        .attr("text-anchor", "start")

}
