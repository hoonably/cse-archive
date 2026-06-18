class lineChart {

    constructor() {
        this.allData = null;
        this.currentData = null;
        this.yExtent = null;
        this.currentCountry = null;
    }

    initData(data) {
        try {

            this.allData = data
            this.currentCountry = "Afghanistan"

            this.drawLineChart()

        }
        catch (error) {
            console.error(error);
        };
    }


    drawLineChart() {
        // Filter data based on the country
        const filteredData = this.allData.filter(d => {
            return d.location == this.currentCountry
        })

        this.currentData = filteredData;
        console.log(this.currentData)

        // Canvas Size
        const margin = { top: 5, right: 50, bottom: 50, left: 120 },
            width = 1400 - margin.left - margin.right,
            height = 600 - margin.top - margin.bottom;

        // Define the position of the chart 
        const svg = d3.select("#linechart")
            .append("svg")
            .attr('width', width + margin.left + margin.right)
            .attr('height', height + margin.top + margin.bottom)
            .append("g")
            .attr("class", "line-g")
            .attr("transform", `translate(${margin.left},${margin.top})`);

        // Define scales
        this.yExtent = [0, d3.max(this.currentData, function (d) { return d.total_cases })];
        const xScale = d3.scaleTime().domain(d3.extent(this.currentData, function (d) { return d.date })).range([0, width]);
        const yScale = d3.scaleLinear().domain(this.yExtent).range([height, 0]);


        // Draw X Axis
        svg.append("g")
            .attr("class", "line-x-axis")
            .attr("transform", "translate(0," + height + ")")
            .call(d3.axisBottom(xScale))
            .append('text')
            .attr('text-anchor', 'middle')
            .text('Date');

        // Draw Y Axis
        svg.append("g")
            .attr("class", "line-y-axis")
            .call(d3.axisLeft(yScale));


        // Draw lines
        svg.append("path")
            .datum(this.currentData)
            .attr("fill", "none")
            .attr("stroke", "steelblue")
            .attr("class", "line")
            .attr("stroke-width", 1.5)
            .attr("d", d3.line()
                .x(function (d) { return xScale(d.date) })
                .y(function (d) { return yScale(d.total_cases) })
            )


    }

    // [Your Code Here]
    // Define method for zooming with the date List from context chart
    zoomChart(dateList) {
        //! With those times, the method in the Focus line chart must redraw(or zoom) the line chart.
        //! (6pts)
        const filteredData = this.currentData.filter(d => {
            return d.date >= dateList[0] && d.date <= dateList[1]
        })
        
        //* canvas size는 drawLineChart 함수랑 동일하게
        const margin = { top: 5, right: 50, bottom: 50, left: 120 },
            width = 1400 - margin.left - margin.right,
            height = 600 - margin.top - margin.bottom;

        //! The x-axis must change following the zoom. The minimum and the maximum values of the
        //! x-axis should be the times calculated above. (6pts)
        const xScale = d3.scaleTime().domain(d3.extent(filteredData, function (d) { return d.date })).range([0, width]);

        //! The zooming must happen only in the x-axis. The y-axis must stay the same. (3pts)
        const yScale = d3.scaleLinear().domain(this.yExtent).range([height, 0]);

        d3.select(".line-x-axis")
            .call(d3.axisBottom(xScale));

        d3.select(".line")
            .datum(filteredData)
            .attr("d", d3.line()
                .x(function (d) { return xScale(d.date) })
                .y(function (d) { return yScale(d.total_cases) })
            );
    }

    // [Your Code Here]
    // Define method for redrawing the focus line chart
    redrawChart(selectedCountry) {
        d3.select("#linechart").select("svg").remove();  //* delete svg
        this.currentCountry = selectedCountry  //* 현재 나라는 그대로
        this.drawLineChart()  //* redraw
    }
}