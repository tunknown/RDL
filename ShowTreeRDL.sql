declare	@sServer	varchar ( max )=	задать сервер здесь 'http://***.ru'
	,@sUserName	sysname=		задать пользовател€ здесь 'domain\user'
	,@bUseRecent	bit=			0
----------
create	table	#Recent
(	ItemId	uniqueidentifier	)
----------
if	@bUseRecent=	1
	insert
		#Recent	( ItemId )
	select
		ItemId=		ReportId
	from
		ReportServer.dbo.ExecutionLogStorage
	where
		UserName=	@sUserName
	group	by
		ReportId
----------
declare	@gRoot		uniqueidentifier
	,@gRoot1	uniqueidentifier
	,@sDelimeter	varchar ( 36 )
	,@sURL		varchar ( max )
----------
select	@sDelimeter=	'5980A75ACBBE4014BCE4AA7EDD1F0598'
	,@sURL=		@sServer+	'/ReportServer/Pages/ReportViewer.aspx?'
----------
----------
select
	@gRoot=		ItemId
from
	ReportServer.dbo.Catalog
where
		Path=		''		-- clustered index
	and	ParentID	is	null
	and	Type=		1
----------
select
	@gRoot1=	ItemId
from
	ReportServer.dbo.Catalog
where
		ParentID=	@gRoot
	and	Type=		1
----------
select
	c.ItemID
	,c.Type
	,c.Path
--	,c.Name
	,ParentID=	nullif ( c.ParentID , @gRoot1 )
	,c.LinkSourceID
	,Content0=	convert ( varchar ( max ) , convert ( varbinary ( max ) , c.Content ) )
	,Content=	convert ( xml , null )
	,Sequence=	row_number()	over	( order	by	c.Path )
into
	#Catalog
from
	ReportServer.dbo.Catalog	c
	left	join	#Recent		r	on
		r.ItemId=	c.ItemID
where
		c.Type	in	( 1,	2,	4 )
	and	c.ItemID	not	in	( @gRoot,	@gRoot1 )
	and	(	@bUseRecent=	0
		or	r.ItemId	is	not	null
		or	c.Type=		1 )
----------
;with	cte	as
(	select
		c.ItemId
		,c.ParentId
	from
		#Catalog	c
		left	join	#Catalog	p	on
			p.ItemID=	c.ParentID
		and	p.Type=		1
	where
			c.Type	in	( 2,	4 )
	union	all
	select
		p.ItemID
		,p.ParentID
	from
		cte
		,#Catalog	p
	where
		p.ItemID=	cte.ParentId
)
delete
	c
from
	#Catalog	c
	left	join	cte	on
		cte.ItemID=	c.ItemID
where
		cte.ItemID	is	null
----------
update				-- пытаемс€ исключить разный xmlnamespace, дл€ единой обработки
	#Catalog
set
	Content=	convert ( xml , stuff ( Content0 , charindex ( ' xmlns="' , Content0 )+	len ( ' xmlns="' ) , charindex ( '"' , Content0 , charindex ( ' xmlns="' , Content0 )+	len ( ' xmlns="' ) )-	charindex ( ' xmlns="' , Content0 )-	len ( ' xmlns="' ) , '' ) )
where
	Content0	is	not	null
----------
--;with	xmlnamespaces	-- избавились от деклараций, т.к. могут быть одновременно отчЄты с деклараци€ми разных версий SSRS
select
	ItemID
	,ParentId
	,Path
--	,Name
	,Parameters=	case	HasParameter
				when	0	then	'без параметров'
				else			'Х'
						+	convert ( varchar ( 10 ) , Sequence1 )
						+	'-'
						+	Parameter
						+	' {'
						+	case	MultiValue
								when	1	then	case	DataType
												when	'Boolean'	then	'несколько да/нет'
												when	'DateTime'	then	'даты'
												when	'Integer'	then	'числа'
												when	'Float'		then	'числа'
												when	'String'	then	'строки'
												else				'неизвестные'
											end
								else			case	DataType
												when	'Boolean'	then	'да/нет'
												when	'DateTime'	then	'дата'
												when	'Integer'	then	'число'
												when	'Float'		then	'число'
												when	'String'	then	'строка'
												else				'неизвестное'
											end
							end
						+	case	HasList
								when	0	then	''
								else			' из '
										+	case	HasDataset
												when	1	then	'базы'
												else			'списка'
											end
							end
						+	'}'
			end
	,Sequence
into
	#withparams
from
	( select
		ItemID
		,ParentId
		,Path
--		,Name
		,Parameter=	t.x.value ( './Prompt[1]' , 'varchar(256)' )
		,HasParameter=	case
					when	t.x	is	null	then	0
					else					1
				end
		,DataType=	t.x.value ( './DataType[1]' , 'varchar(16)' )
		,MultiValue=	isnull ( t.x.value ( './MultiValue[1]' , 'bit' ) , 0 )
		--,DatasetName=	t.x.value ( './ValidValues[1]/DataSetReference[1]/DataSetName[1]' , 'varchar(256)' )
		,HasDataset=	case
					when	t.x.value ( './ValidValues[1]/DataSetReference[1]/DataSetName[1]' , 'varchar(256)' )	is	null	then	0
					else															1
				end
		,HasList=	case	convert ( varchar ( max ) , t.x.query ( './ValidValues[1]' ) )
					when	''	then	0
					else			1
				end
		,Sequence1=	t.x.value ( 'for $s in . return count(../*[.<<$s])+1' , 'integer' )
		,Sequence
	from
		#Catalog
		outer	apply	content.nodes ( '/Report/ReportParameters/ReportParameter' )	t ( x )
	where
		Type=		2 )	t
----------
-- учитываем и ссылки на отчЄты, имеющие то же тело, но другое название
insert
	#withparams	( ItemID,	ParentId,	Path,	/*Name,	*/Parameters,	Sequence )
select
	c.ItemID
	,c.ParentId
	,c.Path
--	,c.Name
	,w.Parameters
	,c.Sequence
from
	#Catalog	c
	,#withparams	w
where
		c.Type=		4
	and	w.ItemID=	c.LinkSourceID
----------
select
	t.ItemId
	,t.ParentId
--	,t.Path
	,cc.Name
--	,t.Parameters
	,Description=	isnull ( cc.Description+	' ' , '' )+	t.Parameters
	,t.Sequence
	,t.URL
from
	( select
		ItemId
		,ParentId
		,Path
--		,Name
		,Parameters=	left ( Parameters , len ( Parameters )-		1 )
		,Sequence
		,URL=		@sURL+	Path+	'&rs:Command=Render'+	case
										when	Path	like	'%/HTML4.0/%'	then	'&rs:Format=HTML4.0'
										when	Path	like	'%/MHTML/%'	then	'&rs:Format=MHTML'
										when	Path	like	'%/IMAGE/%'	then	'&rs:Format=IMAGE'
										when	Path	like	'%/EXCEL/%'	then	'&rs:Format=EXCEL'
										when	Path	like	'%/EXCELOPENXML/%'	then	'&rs:Format=EXCELOPENXML'
										when	Path	like	'%/WORD/%'	then	'&rs:Format=WORD'
										when	Path	like	'%/CSV/%'	then	'&rs:Format=CSV'
										when	Path	like	'%/PDF/%'	then	'&rs:Format=PDF'
										when	Path	like	'%/XML/%'	then	'&rs:Format=XML'
										when	Path	like	'%/NULL/%'	then	'&rs:Format=NULL'
										else						''
									end
	from
		( select
			ItemId
			,ParentId
			,Path
--			,Name
			,Parameters=	replace ( replace ( (	select
									[data()]=	Parameters+	@sDelimeter
								from
									#withparams
								where
									ItemId=	t.ItemId
								for
									xml	path ( '' ) ),	@sDelimeter+	' ',	',' ),	@sDelimeter,	',' )
			,Sequence
		from
			#withparams	t
		group	by
			ItemId
			,ParentId
			,Path
--			,Name
			,Sequence )	t
	union	all
	select
		ItemId
		,ParentId
		,Path
--		,Name
		,null
		,Sequence
		,URL=	null
	from
		#Catalog
	where
		Type=	1 )	t
	inner	join	ReportServer.dbo.Catalog	cc	on
		cc.Path=	t.Path
order	by
	t.Sequence
----------
drop	table
	#Catalog
	,#withparams
	,#Recent