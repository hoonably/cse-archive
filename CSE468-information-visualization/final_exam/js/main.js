const line = new lineChart();
const lineBr = new lineBrush();

d3.csv('../data/owid-covid-data.csv').then(data => {

    var filteredData = data.filter(d => {
        return d.total_cases && d.date && d.location && d.continent
    })

    filteredData = filteredData.map(d => {
        return {
            location: d.location,
            date: d3.timeParse("%Y-%m-%d")(d.date),
            total_cases: Number(d.total_cases),
        }
    })

    line.initData(filteredData);
    lineBr.initData(filteredData);
    initDropdown(filteredData);
})
    .catch(error => {
        console.error(error);
    });

function initDropdown(data) {

    const countryList = []
    // [Your Code Here]
    // Get the list of countries in the data and put it in the countryList 
    //! You have to generate the list of countries in the dataset and put it in the dropdown. (4pts)
    for (var d of data) {
        if (!countryList.includes(d.location)) {  // 모든 데이터이므로 중복 없게 넣어야함
            countryList.push(d.location)
        }
    }

    var dropdownContent = document.getElementById("myDropdown");

    // Generate dropdown contents from dataset
    countryList.forEach(function (d) {
        var link = document.createElement("a");
        link.href = "#";
        link.textContent = d
        link.onclick = function () {
            // [Your Code Here]
            // Call function for redrawing charts
            //! When you click the country in the dropdown list, the system should delete the current line
            //! charts and redraw the both line charts with the data of selected country. (3pts each)
            line.redrawChart(d)
            lineBr.redrawChart(d)
        };
        dropdownContent.appendChild(link);
    });
}

function toggleDropdown() {
    var input = document.getElementById("myInput");
    input.style.display = input.style.display == 'block' ? 'none' : 'block';
    document.getElementById("myDropdown").classList.toggle("show");
}

function filterFunction() {
    var input, filter, ul, li, a, i;
    input = document.getElementById("myInput");
    filter = input.value.toUpperCase();
    div = document.getElementById("myDropdown");
    a = div.getElementsByTagName("a");
    for (i = 0; i < a.length; i++) {
        txtValue = a[i].textContent || a[i].innerText;
        if (txtValue.toUpperCase().indexOf(filter) > -1) {
            a[i].style.display = "";
        } else {
            a[i].style.display = "none";
        }
    }
}
