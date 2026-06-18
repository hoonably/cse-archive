class lineBrush {

    constructor() {
        this.data = null;
        this.currentCountry = null;
    }

    initData(data) {
        try {

            this.data = data
            this.currentCountry = "Afghanistan"

            this.drawLineBrush()

        }
        catch (error) {
            console.error(error);
        };
    }


    drawLineBrush() {
        // Filter data
        const filteredData = this.data.filter(d => {
            return d.location == this.currentCountry
        })

        // Canvas Size
        const margin = { top: 5, right: 50, bottom: 50, left: 120 },
            width = 1400 - margin.left - margin.right,
            height = 100 - margin.top - margin.bottom;

        // Define the position of the chart 
        const svg = d3.select("#linebrush")
            .append("svg")
            .attr('width', width + margin.left + margin.right)
            .attr('height', height + margin.top + margin.bottom)
            .append("g")
            .attr("transform", `translate(${margin.left},${margin.top})`);

        // [Your Code Here]
        // Add brush event
        //! You have to implement a brush interaction in the Context line chart. (4pts)
        svg.call(d3.brushX()
                    .extent([[0, 0], [width, height]])
                    .on("end", brushed)
                )

        // Define Scales
        var xScale = d3.scaleTime().domain(d3.extent(filteredData, function (d) { return d.date })).range([0, width]);
        var yScale = d3.scaleLinear().domain([0, d3.max(filteredData, function (d) { return d.total_cases })]).range([height, 0]);

        // Draw X Axis
        svg.append("g")
            .attr("transform", "translate(0," + height + ")")
            .call(d3.axisBottom(xScale))
            .append('text')
            .attr('text-anchor', 'middle')
            .text('Date');

        // Draw lines
        svg.append("path")
            .datum(filteredData)
            .attr("fill", "none")
            // .attr("style", "outline: thin solid black;")
            .attr("stroke", "steelblue")
            .attr("stroke-width", 1.5)
            .attr("d", d3.line()
                .x(function (d) { return xScale(d.date) })
                .y(function (d) { return yScale(d.total_cases) })
            )

        // [Your Code Here]
        // Define function generating date list and sending it to the method in focus line chart
        function brushed(event) {
            const selection = event.selection;
            if (selection) {
                //! As you brush in the Context line chart, the chart should calculate the time where the left-
                //! end of the brushed area points, and the time where the right-end of the brushed area points.
                //! (4pts)
                const dateList = [xScale.invert(selection[0]), xScale.invert(selection[1])]

                //! After calculating the times, the function should send them to the method in the Focus line
                //! chart class. (2pts)
                line.zoomChart(dateList);
            }
            else {
                //! When you clear the brush, the Focus chart should go back to default state, showing the
                //! overview of the data. (5pts)
                line.redrawChart(line.currentCountry);
                return;
            }
        }

    }

    // [Your Code Here]
    // Define method for redrawing context line chart for brushing
    redrawChart(selectedCountry) {
        d3.select("#linebrush").select("svg").remove();  //* delete svg
        this.currentCountry = selectedCountry;  //* 현재 나라는 그대로
        this.drawLineBrush();  //* redraw
    }

}